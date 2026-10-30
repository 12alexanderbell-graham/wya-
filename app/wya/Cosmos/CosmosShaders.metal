#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: noise
inline float h21(float2 p) { p = fract(p * float2(127.1, 311.7)); p += dot(p, p + 34.53); return fract(p.x * p.y); }
inline float vn(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(h21(i), h21(i + float2(1, 0)), u.x), mix(h21(i + float2(0, 1)), h21(i + float2(1, 1)), u.x), u.y);
}
inline float fbm5(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) { v += a * vn(p); p = float2(p.x * 1.6 - p.y * 1.2, p.x * 1.2 + p.y * 1.6) + 11.7; a *= 0.5; }
    return v;
}
inline float ridged(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { float n = 1.0 - abs(vn(p) * 2.0 - 1.0); v += a * n * n; p = p * 2.07 + 5.3; a *= 0.5; }
    return v;
}

// MARK: THE SUN: a ball of plasma, realistic as Apple Maps draws things, warm like the real one (yellow-white at the centre, an
// orange surface that churns, orange prominences looping off the limb that grow, drift and fall back), never a flat
// yellow fill, never a dark outline. It is your streak: - flare 0...1: the streak's length (8 weeks = 1, the cap); the
// prominences reach further and rise higher with it - glow 0...1: the sun picked; a warm halo grows round it and the
// corona brightens The plasma round the limb is always moving: tongues rise off the edge, swell and fall back. The
// plasma itself, in any three colours (the sun's: cream, yellow, red; a star's: whites)
static half4 plasma(float2 position, float2 size, float t, float discFraction, float flare, float glow,
                    float3 core, float3 yel, float3 red, float cellScale = 1.0) {
    float2 c = size * 0.5;
    float R = min(size.x, size.y) * 0.5 * discFraction;
    float2 q = (position - c) / R;
    float r = length(q);
    float rmax = 1.0 / discFraction;                       // the frame's edge, in disc radii
    float3 org = mix(yel, red, 0.42);
    float3 deep = mix(yel, red, 0.72);
    float aa = 1.5 / R;
    float3 discCol = core;
    float discA = 0.0;
    if (r < 1.0 + aa) {
        float z = sqrt(max(0.0, 1.0 - r * r));
        float2 sp = q / (z + 0.35) * cellScale;
        float2 w = float2(fbm5(sp * 3.0 + t * 0.07), fbm5(sp * 3.0 + 4.0 - t * 0.06));
        float gran = fbm5(sp * 7.0 + w * 2.4 + t * 0.05);
        float cells = vn(sp * 26.0 + w * 3.0 + t * 0.12);
        float tex = gran * 0.65 + cells * 0.35;
        float3 base = mix(core, yel, smoothstep(0.05, 0.8, r));
        base = mix(base, org, smoothstep(0.55, 1.0, r));
        float3 lanes = mix(base, deep, 0.55);
        discCol = mix(lanes, base * 1.04, smoothstep(0.25, 0.75, tex));
        // brighter at the middle, like the real disc; a little brighter all over when picked
        discCol = mix(discCol, core, (1.0 - smoothstep(0.0, 0.45, r)) * 0.55 + glow * 0.12);
        discA = smoothstep(1.0 + aa, 1.0 - aa, r);
    }
    float d = max(0.0, r - 1.0);
    float a = atan2(q.y, q.x);
    float2 dirv = float2(cos(a), sin(a));
    float drift = t * 0.05;
    // how far the plasma reaches off the limb: a tight rim with no streak, up to about a disc's width at the cap
    float reach = 1.0 + 1.6 * flare;
    // each tongue swells and falls back on its own slow beat, so the edge is never still
    float beat = 0.55 + 0.45 * sin(t * 0.7 + fbm5(dirv * 1.7 + 3.0) * 9.0);
    float dd = d / reach;
    float n1 = ridged(dirv * 2.6 + float2(drift, -drift * 0.7) + float2(0.0, dd * 3.5 - t * 0.22));
    float n2 = fbm5(float2(a * 3.0 + drift * 2.0, dd * 5.0 - t * 0.30));
    float flames = smoothstep(0.34, 0.74, n1 * 0.72 + n2 * 0.5) * exp(-dd * (4.6 - 1.6 * beat));
    float strand = smoothstep(0.55, 0.92, ridged(float2(a * 2.4, dd * 9.0) + float2(drift * 3.0, -t * 0.4))) * exp(-dd * 5.0) * 0.85;
    float corona = exp(-d * 16.0) * (0.95 + 0.05 * glow) + exp(-d * 6.0) * (0.16 + 0.22 * glow);
    // the halo when picked: warm light round the sun, never a blob (it falls off fast and stays thin at its edge)
    float halo = glow * (exp(-d * 2.6) * 0.38 + exp(-d * 1.2) * 0.10);
    float lum = clamp(corona + flames + strand + halo, 0.0, 1.0);
    // gone well inside the frame's edge, so its square is never seen
    lum *= 1.0 - smoothstep(rmax * 0.78, rmax * 0.98, r);
    float3 outCol = mix(org, deep, clamp(dd * 3.0, 0.0, 1.0));
    outCol = mix(outCol, yel, clamp(corona * 0.5 + halo, 0.0, 1.0));
    // premultiplied, as SwiftUI takes it; the plasma off the limb is light, so it adds more colour than it covers
    // (rgb above alpha), which keeps its faint parts glowing instead of reading as a brown haze
    float3 col = discCol * discA + outCol * lum * (1.0 - discA);
    float alpha = discA + lum * 0.55 * (1.0 - discA);
    return half4(half3(col), half(alpha));
}

// THE SUN LIVES A STAR'S LIFE AS THE STREAK GROWS. `heat` 0...1 is the star's age (SunView.heat: 1 week 0.13, 4 weeks
// 0.40, 10 weeks 0.62, a year 0.85, ten years 1), smooth in the weeks, most of it spent in the first ten weeks, so
// every week is a clear step: - our sun in its prime (0 to about 3 weeks): yellow, brighter and more alive every week,
// flares reaching out - it swells into a red giant (about 3 to 10 weeks): bigger, orange to red, huge slow cells,
// calmer flares - it turns white (about 3 months to 10 years): the same big star burns white-hot, its surface boils
// fast and a white corona reaches further every year. No rings, no shells, nothing round it but its own light. `swell`
// (from the view): how far the giant may grow here (less at 50%, where Earth's moon is close below).
[[ stitchable ]] half4 sunPlasma(float2 position, half4 colour, float2 size, float t, float discFraction, float flare,
                                 float glow, float heat, float swell) {
    float3 cream = float3(1.0, 0.975, 0.86), yel = float3(1.0, 0.878, 0.290) /* FFE04A */,
           red = float3(0.851, 0.310, 0.239) /* D94F3D */, white = float3(1.0, 1.0, 0.985);
    float prime = smoothstep(0.0, 0.35, heat);
    float big = smoothstep(0.33, 0.62, heat);            // how swollen it is; it never shrinks back
    float giant = big * (1.0 - smoothstep(0.66, 0.95, heat));   // how red it is
    float whiteHot = smoothstep(0.66, 1.0, heat);        // how white it burns

    float scale = 1.0 + 0.55 * big * swell;
    float3 core = mix(cream, white, prime * 0.35);
    float3 y2 = yel, r2 = red;
    core = mix(core, mix(yel, red, 0.25), giant);
    y2 = mix(y2, mix(yel, red, 0.5), giant);
    r2 = mix(r2, red * 0.8, giant);
    core = mix(core, white, whiteHot);
    y2 = mix(y2, mix(white, cream, 0.5), whiteHot);
    r2 = mix(r2, mix(yel, cream, 0.25), whiteHot);
    float speed = (0.7 + 0.9 * prime) * (1.0 - 0.6 * giant) + 1.4 * whiteHot;
    float cells = mix(mix(1.0, 0.42, giant), 1.15, whiteHot);
    float fl = flare * (1.0 - 0.55 * giant);
    half4 base = plasma(position, size, t * speed, discFraction * scale, fl, glow, core, y2, r2, cells);

    float2 c = size * 0.5;
    float R = min(size.x, size.y) * 0.5 * discFraction;
    float2 q = (position - c) / R;
    float r = length(q);
    float rs = r / scale;                                  // in the star's own radii
    float rmax = 1.0 / discFraction;
    float a = atan2(q.y, q.x);
    float2 dirv = float2(cos(a), sin(a));
    float edgeFade = 1.0 - smoothstep(rmax * 0.80, rmax * 0.98, r);
    float outside = smoothstep(1.0, 1.04, rs);
    float d = max(0.0, rs - 1.0);

    // the corona: white streamers from the first week, quieter while it is a red giant, then reaching further every
    // year as it burns white (about one star radius at 1.5 years, two at ten)
    float cor = smoothstep(0.03, 0.3, heat) * (1.0 - 0.7 * giant) + 0.9 * whiteHot;
    float len = 0.35 + 0.9 * smoothstep(0.03, 0.3, heat) + 1.1 * whiteHot;
    float bigS = smoothstep(0.42, 0.85, fbm5(dirv * 2.2 + float2(t * 0.012, -t * 0.009)));
    float fine = smoothstep(0.5, 0.95, ridged(float2(a * 9.0 + t * 0.01, d * 0.6 - t * 0.03)));
    float coronaL = cor * ((bigS * 0.75 + fine * 0.35) * exp(-d / len) + exp(-d / (len * 0.35)) * 0.35) * outside * edgeFade;

    // the giant's warm haze; the white star's bright glow
    float hazeL = giant * exp(-d * 2.2) * 0.55 * outside * edgeFade;
    float glowL = whiteHot * exp(-d * 3.0) * 0.6 * outside * edgeFade;

    float er = 0.0;   // no loops: they read as rings
    float period = mix(10.0, 5.0, smoothstep(0.15, 0.4, heat));
    float k = floor(t / period);
    float ph = fract(t / period);
    float a0 = h21(float2(k, 3.1)) * 6.2831853;
    float2 d0 = float2(cos(a0), sin(a0)) * scale;
    float rise = sin(ph * 3.14159265);
    float rl = (0.18 + 0.7 * rise) * scale;
    float2 cp = d0 * (1.0 + rl * 0.15 / scale);
    float ringE = abs(length(q - cp) - rl);
    float above = smoothstep(-0.1, 0.25, dot(q - d0, normalize(d0)));
    float loopL = er * exp(-ringE * 26.0 / scale) * rise * above * outside * edgeFade;

    float3 hazeCol = mix(yel, red, 0.45);
    float3 light = mix(cream, white, 0.6) * coronaL * 0.55 + hazeCol * hazeL + white * glowL + yel * loopL;
    float add = clamp(coronaL * 0.55 + hazeL + glowL + loopL, 0.0, 1.0);
    float ba = float(base.a);
    float3 col = float3(base.rgb) + light * (1.0 - ba * 0.7);
    float alpha = clamp(ba + add * 0.55 * (1.0 - ba), 0.0, 1.0);
    return half4(half3(min(col, float3(alpha * 1.6))), half(alpha));
}

// A STAR IS THE SUN'S PLASMA, ONLY THE PLASMA (; 11:39: "There's no white circle ... It's just the plasma ... stop
// putting them at 50% opacity"): the sun's tongues and corona with no disc, all white, at full strength
[[ stitchable ]] half4 starPlasma(float2 position, half4 colour, float2 size, float t, float discFraction, float flare) {
    float2 c = size * 0.5;
    float R = min(size.x, size.y) * 0.5 * discFraction;
    float2 q = (position - c) / R;
    float r = length(q);
    float rmax = 1.0 / discFraction;
    float d = r;                                            // measured from the middle: the light starts there
    float a = atan2(q.y, q.x);
    float2 dirv = float2(cos(a), sin(a));
    float drift = t * 0.05;
    float reach = 1.0 + 1.6 * flare;
    float beat = 0.55 + 0.45 * sin(t * 0.7 + fbm5(dirv * 1.7 + 3.0) * 9.0);
    float dd = d / reach;
    float n1 = ridged(dirv * 2.6 + float2(drift, -drift * 0.7) + float2(0.0, dd * 3.5 - t * 0.22));
    float n2 = fbm5(float2(a * 3.0 + drift * 2.0, dd * 5.0 - t * 0.30));
    float flames = smoothstep(0.34, 0.74, n1 * 0.72 + n2 * 0.5) * exp(-dd * (4.6 - 1.6 * beat));
    float strand = smoothstep(0.55, 0.92, ridged(float2(a * 2.4, dd * 9.0) + float2(drift * 3.0, -t * 0.4))) * exp(-dd * 5.0) * 0.85;
    float corona = exp(-d * 3.2);
    float lum = clamp(corona + flames + strand, 0.0, 1.0);
    lum *= 1.0 - smoothstep(rmax * 0.78, rmax * 0.98, r);
    return half4(half3(lum), half(lum));
}

// MARK: A PLANET: a real sphere lit by one light, wearing its NASA surface map (public domain), graded to style A:
// realistic, but softened toward pastel colours. Like a moon phase it
// darkens as you stamp more of its continent; Earth's night side shows its city lights.
[[ stitchable ]] half4 planetSphere(float2 position, half4 colour, float2 size, float spin, float3 light,
                                    texture2d<half> surface, texture2d<half> nightLights, float hasLights, float bands) {
    float2 c = size * 0.5;
    float R = min(size.x, size.y) * 0.5;
    float2 q = (position - c) / R;
    float r2 = dot(q, q);
    if (r2 >= 1.0) return half4(0);
    float z = sqrt(1.0 - r2);
    float3 n = float3(q.x, -q.y, z);
    // a slight tilt, then the turning
    float tilt = 0.22;
    float3 nt = float3(n.x, n.y * cos(tilt) - n.z * sin(tilt), n.y * sin(tilt) + n.z * cos(tilt));
    float lon = atan2(nt.x, nt.z) + spin;
    float lat = asin(clamp(nt.y, -1.0, 1.0));
    float2 uv = float2(fract(lon / (2.0 * M_PI_F) + 0.5), 0.5 - lat / M_PI_F);
    constexpr sampler s(address::repeat, filter::linear);
    float3 albedo = float3(surface.sample(s, uv).rgb);
    // the pastel grade: lifted shadows, softer colour
    float lumA = dot(albedo, float3(0.299, 0.587, 0.114));
    albedo = mix(float3(lumA), albedo, 0.82);
    albedo = albedo * 0.86 + 0.12;
    // the light: `light` is the way to the sun (x across, y up, z towards you), so the lit side turns with the sun's
    // direction and can never flip
    float3 L = normalize(light + float3(0.0, 0.06, 0.0));
    float lambert = dot(n, L);
    float day = smoothstep(-0.06, 0.10, lambert);
    float shade = 0.55 + 0.45 * clamp(lambert, 0.0, 1.0);
    float3 col = albedo * shade * day;
    // the night side: darker, with enough light that the planet still reads; Earth's cities glow there
    float3 nightCol = albedo * 0.30;
    if (hasLights > 0.5) {
        float lights = float(nightLights.sample(s, uv).r);
        nightCol += float3(1.0, 0.88, 0.62) * lights * 0.85;
    }
    col += nightCol * (1.0 - day);
    // a soft rim, the atmosphere's edge
    float rim = pow(1.0 - z, 3.0);
    col += float3(0.95, 0.97, 1.0) * rim * 0.18 * day;
    // anti-aliased edge
    float edge = smoothstep(1.0, 1.0 - 1.5 / R, sqrt(r2));
    return half4(half3(col * edge), half(edge));
}

// MARK: Saturn's ring, from its real colours (saturn-ring.png, one row), seen at a slant. `front` draws only the half
// that passes in front of the planet.
[[ stitchable ]] half4 saturnRing(float2 position, half4 colour, float2 size, float tiltY, float front,
                                  texture2d<half> ring) {
    float2 c = size * 0.5;
    float2 q = (position - c) / (size.x * 0.5);
    q.y /= tiltY;
    float r = length(q);
    float inner = 0.52, outer = 1.0;
    if (r < inner || r > outer) return half4(0);
    bool isFront = q.y > 0.0;
    if ((front > 0.5) != isFront) return half4(0);
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    half4 rc = ring.sample(s, float2((r - inner) / (outer - inner), 0.5));
    return half4(rc.rgb * rc.a, rc.a);
}

