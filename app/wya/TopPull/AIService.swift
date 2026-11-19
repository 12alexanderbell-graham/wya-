import Foundation
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// THE IN-APP AI IS THE CLAUDE API. One question in, one answer out: words and the places it names, which the field
/// shows as rows you can open. It answers from what you have done. WHERE IT CONNECTS: the key is never written in the
/// code. For building, the simulator is started with ANTHROPIC_API_KEY in its environment; a build can carry
/// WYAClaudeKey in Info.plist. FOR LAUNCH the app must not carry a key at all: WYAAIBase in Info.plist points at our
/// own small server, which adds the key and passes the same request on (same path, same body), so the code here does
/// not change. With neither, the AI says it isn't connected.
nonisolated enum AIService {
    struct Turn: Codable, Sendable, Equatable {
        var role: String        // "user" or
        var text: String
        var image: Data? = nil  // a JPEG the user attached (user turns only)
    }
    struct Place: Codable, Sendable, Equatable, Hashable {
        var cc: String
        var name: String
        var why: String
        /// the first-level region it is in (its own name when it is one; "" for a whole country)
        var region: String = ""
    }
    /// THE SAME ANSWER AT FOUR LENGTHS, made in one go: dragging the answer smaller or bigger only picks another of
    /// these
    struct Answer: Codable, Sendable, Equatable {
        /// the default length (about 60 words)
        var answer: String
        var places: [Place]
        /// one to four words: "Yes."
        var core: String = ""
        /// one sentence
        var short: String = ""
        /// the fuller version (up to about 150 words)
        var long: String = ""

        init(answer: String, places: [Place], core: String = "", short: String = "", long: String = "") {
            self.answer = answer; self.places = places; self.core = core; self.short = short; self.long = long
        }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            answer = try c.decode(String.self, forKey: .answer)
            places = try c.decodeIfPresent([Place].self, forKey: .places) ?? []
            core = try c.decodeIfPresent(String.self, forKey: .core) ?? ""
            short = try c.decodeIfPresent(String.self, forKey: .short) ?? ""
            long = try c.decodeIfPresent(String.self, forKey: .long) ?? ""
        }
        /// 0 the core, 1 short, 2 the answer, 3 long (a missing one falls back to the answer)
        func text(_ level: Int) -> String {
            let t = [core, short, answer, long][max(0, min(3, level))]
            return t.isEmpty ? answer : t
        }
        static let levels = 4
    }
    enum Failure: Error, Equatable {
        case notConnected, badKey, busy, offline, refused, server(Int), unreadable
        /// what the field says, in plain words
        var words: String {
            switch self {
            case .notConnected: "The AI isn't connected yet."
            case .badKey: "The AI's key was refused."
            case .busy: "The AI is busy. Try again in a moment."
            case .offline: "No connection."
            case .refused: "The AI can't help with that one."
            case .server(let c): "The AI didn't answer (\(c))."
            case .unreadable: "The AI's answer couldn't be read."
            }
        }
    }

    static let model = "claude-opus-5-5"
    static let version = "2026-10-21"

    /// the key and where to send it; nil: not connected
    static var connection: (base: URL, key: String?)? {
        let info = Bundle.main.infoDictionary ?? [:]
        let env = ProcessInfo.processInfo.environment
        let key = [env["ANTHROPIC_API_KEY"], info["WYAClaudeKey"] as? String]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("$(") }
        if let b = (info["WYAAIBase"] as? String).flatMap({ URL(string: $0) }), b.scheme == "https" {
            return (b, key)  // our server holds the key; one here is only sent if a build carries it
        }
        guard let key else { return nil }
        return (URL(string: "https://api.anthropic.com")!, key)
    }
    static var connected: Bool { connection != nil }

    /// what it knows about you, written once per question (stable words first, so a follow-up reuses the cache)
    struct Context: Sendable {
        var stamped: [String] = []
        var lived: [String] = []
        var wished: [String] = []
        var nationalities: [String] = []
        var name: String = ""
        var screen: String = ""
        /// the trip going on or coming next, with what is planned (it outranks the latest stamp, audit L15634)
        var trip: String = ""
        /// their other plans and lists, by name and places
        var plans: [String] = []
        /// what they told it to remember, in their words
        var notes: [String] = []
    }

    static func instructions(_ c: Context) -> String {
        // HOW IT TALKS
        var s = """
        You live inside wya?!, an app where people keep the places they've been and plan where to go next. You have \
        no name and you never call yourself an AI or an assistant.

        Talk like a normal person who has travelled a lot and really knows the world. Not like an AI.

        - Be direct. The first sentence answers what they asked. No warm-up, no restating the question, no "great \
        question", no summary at the end, no offers like "let me know" or "would you like me to".
        - Keep it short. Usually one to three sentences. Never more than about 60 words. If a word or a number \
        answers it, give just that. Every sentence has to earn its place: cut side notes and tangents that don't \
        help with what they asked.
        - Say why. When you suggest somewhere, say what is actually there and why it is worth the trip for them, \
        in concrete terms. No adjectives doing the work instead of facts.
        - Never give the boring, expected answer. Skip the first thing everyone would say unless it really is the \
        best fit for this person, and then say why it beats the rest.
        - Think before you answer. Check it is true, current enough and right for this person. Take a position. \
        Disagree when they have something wrong.
        - Never lie or pretend. Don't invent places, numbers, prices or rules. If you don't know or it may have \
        changed (visas, prices, safety, opening times), say so plainly.
        - Plain words. No brochure language (hidden gem, nestled, vibrant, breathtaking, must-see, bucket list, \
        off the beaten path), no hype, no headings, no lists, no markdown, no emoji.
        - Learn the person. Use what you know about them below to judge what they would like, and let it shape the \
        pick. Mention it only when it explains the pick; don't recite their history back to them.
        - Don't interview them. When a question could mean a few things, pick the likeliest reading and answer it; \
        ask back only when two readings would lead to different things that are hard to undo, and then in one short \
        question.
        - Don't tell them what is already on their screen; add to it.
        - Answer anything they ask, travel or not, in the same way. Don't steer other questions back to travel.
        - Reply in the language they write in.

        Write the same answer at four lengths, with the same view in all of them: "core" is only its heart in one \
        to four words ("Yes.", "Lisbon.", "Kangchenjunga, 8,586 m."); "short" is one sentence; "answer" is your \
        normal answer as above; "long" is the fuller version, up to about 150 words, with more reasons, details and \
        options, and still no padding.

        Put the places your answer suggests or talks about in "places": cc is the lowercase ISO 3166-1 alpha-2 code \
        of the country it is in; name is the place's own name (the country's name when it is the country); why is at \
        most 6 plain words; region is the English name of the first-level division it is in (state, province, \
        republic, oblast, region; its own name when it is one; empty for a whole country). At most 4, in the order \
        you'd go; none when the answer names no place. Write each of these places into the answer under exactly \
        the same name, so it can be tapped there.
        """
        var me: [String] = []
        if !c.name.isEmpty { me.append("Their name: \(c.name).") }
        if !c.nationalities.isEmpty { me.append("Nationality: \(c.nationalities.joined(separator: ", ")).") }
        if !c.lived.isEmpty { me.append("Lived in: \(c.lived.joined(separator: ", ")).") }
        if !c.stamped.isEmpty { me.append("Been to (\(c.stamped.count)): \(c.stamped.joined(separator: ", ")).") }
        if !c.wished.isEmpty { me.append("Wants to go to: \(c.wished.joined(separator: ", ")).") }
        if !c.notes.isEmpty { me.append("They told you to remember: \(c.notes.joined(separator: "; ")).") }
        if !c.trip.isEmpty { me.append("Their trip (what they are doing now or next; it matters more than where they've been): \(c.trip)") }
        if !c.plans.isEmpty { me.append("Their other plans and lists: \(c.plans.joined(separator: "; ")).") }
        if !me.isEmpty { s += "\n\nAbout this person:\n" + me.joined(separator: "\n") }
        return s
    }

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "core": ["type": "string"],
            "short": ["type": "string"],
            "answer": ["type": "string"],
            "long": ["type": "string"],
            "places": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "cc": ["type": "string"],
                        "name": ["type": "string"],
                        "why": ["type": "string"],
                        "region": ["type": "string"],
                    ],
                    "required": ["cc", "name", "why", "region"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["core", "short", "answer", "long", "places"],
        "additionalProperties": false,
    ]

    /// asks Claude: the earlier turns of this sitting, then the question (and its picture)
    static func ask(_ turns: [Turn], context: Context, effort: String = "medium") async -> Result<Answer, Failure> {
        guard let conn = connection else { return .failure(.notConnected) }
        var messages: [[String: Any]] = turns.map { t in
            guard t.role == "user", let img = t.image else { return ["role": t.role, "content": t.text] }
            return ["role": "user", "content": [
                ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg",
                                             "data": img.base64EncodedString()]],
                ["type": "text", "text": t.text.isEmpty ? "What is this, and where is it?" : t.text],
            ]]
        }
        // what is on the screen right now goes with the newest question only (it changes, so it never sits in the
        // cached part, Part 19:)
        if !context.screen.isEmpty {
            messages.append(["role": "system", "content": "On their screen right now: \(context.screen)"])
        }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4000,
            "system": [["type": "text", "text": instructions(context), "cache_control": ["type": "ephemeral"]]],
            "messages": messages,
            // : medium, not low
            "output_config": ["effort": effort, "format": ["type": "json_schema", "schema": schema]],
            // a declined question is asked again of a model the API picks for its kind, in the same call
            "fallbacks": "default",
        ]
        var result = await send(body, conn: conn, beta: "server-side-fallback-2026-07-01")
        // (a server between us that doesn't pass the beta on: once more without it, and without the screen line if
        // that was what it refused)
        if case .failure(.server(400)) = result {
            body["fallbacks"] = nil
            result = await send(body, conn: conn, beta: nil)
            if case .failure(.server(400)) = result, !context.screen.isEmpty {
                body["messages"] = Array(messages.dropLast())
                result = await send(body, conn: conn, beta: nil)
            }
        }
        return result
    }

    private static func send(_ body: [String: Any], conn: (base: URL, key: String?), beta: String?) async -> Result<Answer, Failure> {
        switch await raw(body, conn: conn, beta: beta) {
        case .failure(let f): return .failure(f)
        case .success(let (text, stop)):
            if let d = text.data(using: .utf8), var a = try? JSONDecoder().decode(Answer.self, from: d) {
                a.places = a.places.map { Place(cc: $0.cc.lowercased(), name: $0.name, why: $0.why, region: $0.region) }
                return .success(a)
            }
            // cut short (max_tokens): whatever words there are, no places
            if !text.isEmpty, stop == "max_tokens" { return .success(Answer(answer: text, places: [])) }
            return .failure(.unreadable)
        }
    }

    /// one request: the reply's text (the JSON the schema asked for) and why it stopped
    private static func raw(_ body: [String: Any], conn: (base: URL, key: String?), beta: String?) async -> Result<(String, String?), Failure> {
        var req = URLRequest(url: conn.base.appending(path: "v1/messages"))
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(version, forHTTPHeaderField: "anthropic-version")
        var betas = beta.map { [$0] } ?? []
        if let key = conn.key {
            // a Claude login token (sk-ant-oat…) goes as a bearer token with its beta; an API key as x-api-key
            if key.hasPrefix("sk-ant-oat") {
                req.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
                betas.append("oauth-2025-04-20")
            } else {
                req.setValue(key, forHTTPHeaderField: "x-api-key")
            }
            #if DEBUG
            // only the kind and the length, never the key
            NSLog("wya ai key kind %@ length %d", String(key.prefix(10)), key.count)
            #endif
        }
        if !betas.isEmpty { req.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta") }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return .failure(.unreadable) }
        req.httpBody = data
        let reply: Data, status: Int
        do {
            let (d, r) = try await URLSession.shared.data(for: req)
            reply = d
            status = (r as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            return .failure(.offline)
        }
        #if DEBUG
        NSLog("wya ai status %d, %d bytes", status, reply.count)
        if status != 200 { NSLog("wya ai error %@", String(decoding: reply.prefix(600), as: UTF8.self)) }
        #endif
        switch status {
        case 200: break
        case 401, 403: return .failure(.badKey)
        case 429, 529: return .failure(.busy)
        default:
            return .failure(.server(status))
        }
        guard let json = try? JSONSerialization.jsonObject(with: reply) as? [String: Any] else { return .failure(.unreadable) }
        if json["stop_reason"] as? String == "refusal" { return .failure(.refused) }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        #if DEBUG
        NSLog("wya ai answer %@", text)
        #endif
        return .success((text, json["stop_reason"] as? String))
    }

    // MARK: plans

    /// A PLAN THE AI MAKES
    struct PlanDraft: Codable, Sendable {
        struct Item: Codable, Sendable { var at: String; var what: String; var place: String; var cc: String }
        struct Day: Codable, Sendable { var items: [Item] }
        var name: String
        var note: String
        var days: [Day]
    }
    private static let planSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "name": ["type": "string"],
            "note": ["type": "string"],
            "days": ["type": "array", "items": [
                "type": "object",
                "properties": ["items": ["type": "array", "items": [
                    "type": "object",
                    "properties": ["at": ["type": "string"], "what": ["type": "string"],
                                   "place": ["type": "string"], "cc": ["type": "string"]],
                    "required": ["at", "what", "place", "cc"], "additionalProperties": false,
                ]]],
                "required": ["items"], "additionalProperties": false,
            ]],
        ],
        "required": ["name", "note", "days"], "additionalProperties": false,
    ]

    /// asks for a day-by-day plan; the same voice and the same knowledge of you as an answer
    static func plan(_ request: String, context: Context) async -> Result<PlanDraft, Failure> {
        guard let conn = connection else { return .failure(.notConnected) }
        let ask = """
        \(request)

        Make it a real day-by-day plan to keep in wya. "name" is the plan's short name (usually just the place). \
        "note" is one plain sentence on why it's shaped this way. "days" has as many days as the trip should take; \
        each item is one thing to do, written in a few plain words ("Sulphur baths in Abanotubani", "Marshrutka to \
        Mestia", not sentences); "at" is a time like "09:40" only when the timing matters, otherwise empty; "place" is \
        where it happens; "cc" is its lowercase ISO country code. Two to five items a day, travel days included. The \
        same voice and taste as your answers: never the obvious route when a better one fits this person.
        """
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8000,
            "system": [["type": "text", "text": instructions(context), "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": ask]],
            "output_config": ["effort": "medium", "format": ["type": "json_schema", "schema": planSchema]],
        ]
        switch await raw(body, conn: conn, beta: nil) {
        case .failure(let f): return .failure(f)
        case .success(let (text, _)):
            guard let d = text.data(using: .utf8), let p = try? JSONDecoder().decode(PlanDraft.self, from: d), !p.days.isEmpty
            else { return .failure(.unreadable) }
            return .success(p)
        }
    }

    // MARK: a place page's Suggestions

    struct Pick: Codable, Equatable, Sendable { var name: String; var why: String }
    private static let pickSchema: [String: Any] = [
        "type": "object",
        "properties": ["picks": ["type": "array", "items": [
            "type": "object",
            "properties": ["name": ["type": "string"], "why": ["type": "string"]],
            "required": ["name", "why"], "additionalProperties": false,
        ]]],
        "required": ["picks"], "additionalProperties": false,
    ]

    /// SUGGESTIONS ON A PLACE'S PAGE: up to three of the places on the page, each with why it is worth it for you,
    /// picked only from the page's own list (so every one opens); fewer, or none, rather than filler
    static func suggest(place: String, from names: [String], context: Context) async -> Result<[Pick], Failure> {
        guard let conn = connection else { return .failure(.notConnected) }
        let ask = """
        I'm looking at \(place) in wya. Of these places in it, which are worth going to for me? \
        Pick from this list only, names exactly as written: \(names.joined(separator: "; ")).

        Up to three. For each, "why" is one plain line, at most 12 words, saying why it suits me in particular \
        (from where I've been and want to go), not what it is. Skip the obvious unless it really is the best for me. \
        Only true things: never force a link to a place I've been when there isn't a real one; then just say plainly \
        what makes it worth it. If none suits me better than any other, return none.
        """
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2000,
            "system": [["type": "text", "text": instructions(context), "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": ask]],
            "output_config": ["effort": "medium", "format": ["type": "json_schema", "schema": pickSchema]],
        ]
        switch await raw(body, conn: conn, beta: nil) {
        case .failure(let f): return .failure(f)
        case .success(let (text, _)):
            struct Out: Codable { var picks: [Pick] }
            guard let d = text.data(using: .utf8), let o = try? JSONDecoder().decode(Out.self, from: d) else { return .failure(.unreadable) }
            let known = Set(names.map { $0.lowercased() })
            return .success(Array(o.picks.filter { known.contains($0.name.lowercased()) }.prefix(3)))
        }
    }

    // MARK: a plan's Suggestions

    struct PlanPick: Codable, Equatable, Sendable, Hashable { var what: String; var place: String; var cc: String; var why: String }
    private static let planPickSchema: [String: Any] = [
        "type": "object",
        "properties": ["picks": ["type": "array", "items": [
            "type": "object",
            "properties": ["what": ["type": "string"], "place": ["type": "string"], "cc": ["type": "string"], "why": ["type": "string"]],
            "required": ["what", "place", "cc", "why"], "additionalProperties": false,
        ]]],
        "required": ["picks"], "additionalProperties": false,
    ]

    /// SUGGESTIONS ON A PLAN: up to three things the plan doesn't have yet, near where it goes, each with why it is worth
    /// it for you; none rather than filler
    static func planSuggestions(_ plan: String, context: Context) async -> Result<[PlanPick], Failure> {
        guard let conn = connection else { return .failure(.notConnected) }
        let ask = """
        My plan in wya: \(plan)

        What is worth adding that isn't in it? Up to three things, near where the plan already goes (or a short hop \
        from it). "what" is the thing in a few plain words ("Sulphur baths in Abanotubani", not a sentence); "place" \
        is where it is; "cc" its lowercase ISO country code; "why" one plain line, at most 12 words, on why it's \
        worth it for me. Only true things; skip the obvious unless it really is the best. If nothing really adds to \
        it, return none.
        """
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2000,
            "system": [["type": "text", "text": instructions(context), "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": ask]],
            "output_config": ["effort": "medium", "format": ["type": "json_schema", "schema": planPickSchema]],
        ]
        switch await raw(body, conn: conn, beta: nil) {
        case .failure(let f): return .failure(f)
        case .success(let (text, _)):
            struct Out: Codable { var picks: [PlanPick] }
            guard let d = text.data(using: .utf8), let o = try? JSONDecoder().decode(Out.self, from: d) else { return .failure(.unreadable) }
            return .success(Array(o.picks.filter { !$0.what.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(3)))
        }
    }

    static func listSuggestions(_ list: String, context: Context) async -> Result<[PlanPick], Failure> {
        guard let conn = connection else { return .failure(.notConnected) }
        let ask = """
        My list in wya: \(list)

        What else belongs on it that isn't there? Up to three, the same kind of thing as the list. "what" is its \
        own name only, as you'd write it in the list ("Kazbegi", "Khachapuri"); "place" is where it is when it isn't \
        itself a place, otherwise empty; "cc" its lowercase ISO country code; "why" one plain line, at most 12 words, \
        on why it's worth it for me. Only true things; skip the obvious unless it really is the best. If nothing \
        really belongs, return none.
        """
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2000,
            "system": [["type": "text", "text": instructions(context), "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": ask]],
            "output_config": ["effort": "medium", "format": ["type": "json_schema", "schema": planPickSchema]],
        ]
        switch await raw(body, conn: conn, beta: nil) {
        case .failure(let f): return .failure(f)
        case .success(let (text, _)):
            struct Out: Codable { var picks: [PlanPick] }
            guard let d = text.data(using: .utf8), let o = try? JSONDecoder().decode(Out.self, from: d) else { return .failure(.unreadable) }
            return .success(Array(o.picks.filter { !$0.what.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(3)))
        }
    }

    // MARK: Jev: the quick suggestions, on the phone, never the Claude API

    /// three short things to ask, from what you have done (Apple Intelligence on the phone when it is there; worked
    /// out from your marks otherwise). Never more than 2 s.
    static func suggestions(_ c: Context) async -> [String] {
        let plain = plainSuggestions(c)
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else { return plain }
        let session = LanguageModelSession(instructions: """
            Write three short questions a traveller could ask a travel expert, personal to them. Each at most 6 words, \
            one per line, no numbering, no quotes, no emoji.
            """)
        var about = "Been to: \(c.stamped.prefix(30).joined(separator: ", "))."
        if !c.wished.isEmpty { about += " Wants: \(c.wished.prefix(12).joined(separator: ", "))." }
        let words: String? = await withTaskGroup(of: String?.self) { g in
            g.addTask { (try? await session.respond(to: about))?.content }
            g.addTask { try? await Task.sleep(for: .seconds(2)); return nil }
            let first = await g.next() ?? nil
            g.cancelAll()
            return first
        }
        let lines = (words ?? "").split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-•*\"0123456789."))) }
            .filter { !$0.isEmpty && $0.count <= 48 }
        return lines.count >= 2 ? Array(lines.prefix(3)) : plain
        #else
        return plain
        #endif
    }

    static func plainSuggestions(_ c: Context) -> [String] {
        var out: [String] = []
        if let w = c.wished.first { out.append("Plan me a week in \(w)") }
        if !c.stamped.isEmpty { out.append("Where should my \(ordinal(c.stamped.count + 1)) country be?") }
        if let l = c.lived.first { out.append("Somewhere that feels like \(l)") }
        for f in ["Somewhere nobody I know has been", "A long weekend from home", "Quiet places for this winter"] where out.count < 3 {
            out.append(f)
        }
        return Array(out.prefix(3))
    }

    private static func ordinal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f.string(from: NSNumber(value: n)) ?? "\(n)th"
    }

    #if DEBUG
    /// a made-up answer for looking at the field without spending anything (the test driver's)
    static let mock = Answer(
        answer: "You liked the Alps, so skip Moscow. Fly to Kemerovo for Sheregesh in February: deep powder, cheap lifts. In summer, the Putorana Plateau has canyons and waterfalls almost nobody sees, and Dagestan's mountain villages are a world of their own.",
        places: [
            Place(cc: "ru", name: "Sheregesh", why: "Siberian powder, February", region: "Kemerovo Oblast"),
            Place(cc: "ru", name: "Putorana Plateau", why: "Remote canyons and waterfalls", region: "Krasnoyarsk Krai"),
            Place(cc: "ru", name: "Dagestan", why: "Mountain villages, Caucasus food", region: "Dagestan"),
            Place(cc: "ge", name: "Svaneti", why: "If Russia's visa is a problem", region: "Samegrelo-Zemo Svaneti"),
        ],
        core: "Sheregesh.",
        short: "Skip Moscow: Sheregesh for powder in February, Dagestan in summer.",
        long: "You liked the Alps, so skip Moscow and St Petersburg. Fly to Kemerovo and take the bus up to Sheregesh in February: deep, dry Siberian powder, lifts that cost a third of the Alps, and trees you can ski between. In summer go north instead: the Putorana Plateau is only reachable by boat or helicopter from Norilsk, and its canyons and waterfalls see a few hundred visitors a year. If you want people as much as landscape, Dagestan's mountain villages, Gunib and Chokh, sit on cliffs above the Caspian and feed you like family. Check current travel advice for the North Caucasus before you go.")
    #endif
}

extension UIImage {
    /// small enough to send (the long side 1280, JPEG at 0.8)
    nonisolated func forAI() -> Data? {
        let longSide = max(size.width, size.height)
        let k = min(1, 1280 / max(1, longSide))
        let target = CGSize(width: size.width * k, height: size.height * k)
        let img = UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return img.jpegData(compressionQuality: 0.8)
    }
}
