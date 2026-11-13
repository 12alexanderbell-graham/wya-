import Foundation

/// EACH TERRITORY'S COUNTRY (the old app's world file, `sov`): Greenland's is Denmark. With Territories on "Stamp the
/// country too" (the setting's default), stamping a territory stamps its country with it, only on (unstamping the
/// territory later takes the country away only when nothing else of it holds it), as a town or region stamps its
/// country. "Separate" stamps the territory alone.
nonisolated enum Territories {
    static let sovereign: [String: String] = [
        "ai": "gb", "as": "us", "aw": "nl", "ax": "fi", "bl": "fr", "bm": "gb", "bv": "no", "cc": "au", "ck": "nz",
        "cp": "fr", "cw": "nl", "cx": "au", "fk": "gb", "fo": "dk", "gf": "fr", "gg": "gb", "gi": "gb", "gl": "dk",
        "gp": "fr", "gs": "gb", "gu": "us", "hk": "cn", "hm": "au", "im": "gb", "io": "gb", "je": "gb", "ky": "gb",
        "mf": "fr", "mo": "cn", "mp": "us", "mq": "fr", "ms": "gb", "nc": "fr", "nf": "au", "nu": "nz", "pf": "fr",
        "pm": "fr", "pn": "gb", "pr": "us", "re": "fr", "sh-ac": "gb", "sh-hl": "gb", "sh-ta": "gb", "sj": "no",
        "sx": "nl", "tc": "gb", "tf": "fr", "tk": "nz", "um": "us", "vg": "gb", "vi": "us", "wf": "fr",
        "x-akrotiri": "gb", "x-ashmore-and-cartier-islands": "au", "x-athos": "gr", "x-bq-bo": "nl", "x-bq-sa": "nl",
        "x-bq-se": "nl", "x-coral-sea-islands": "au", "x-dhekelia": "gb", "x-rapa": "cl", "yt": "fr"
    ]
}
