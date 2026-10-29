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

// MARK: THE SUN: a ball of plasma, realistic in the way Apple Maps is, warm like the real one (yellow-white at the centre, an
// orange surface that churns, orange prominences looping off the limb that grow, drift and fall back), never a flat
// yellow fill, never a dark outline. It is your streak: - flare 0...1: the streak's length (8 weeks = 1, the cap); the
// prominences reach further and rise higher with it - glow 0...1: the sun picked; a warm halo grows round it and the
// corona brightens The plasma round the limb is always moving: tongues rise off the edge, swell and fall back. The
// plasma itself, in any three colours (the sun's: cream, yellow, red; a star's: whites)
static half4 plasma(float2 position, float2 size, float t, float discFraction, float flare, float glow,
                    float3 core, float3 yel, float3 red) {
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
        float2 sp = q / (z + 0.35);
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

[[ stitchable ]] half4 sunPlasma(float2 position, half4 colour, float2 size, float t, float discFraction, float flare, float glow) {
    return plasma(position, size, t, discFraction, flare, glow,
                  float3(1.0, 0.975, 0.86), float3(1.0, 0.878, 0.290) /* FFE04A */, float3(0.851, 0.310, 0.239) /* D94F3D */);
}

// A STAR IS THE SUN'S PLASMA, ONLY THE PLASMA: the sun's tongues and corona with no disc, all white, at full strength
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

// MARK: A PLANET: a real sphere lit by one light, wearing its NASA surface map (public domain), graded realistic
// but softened to pastel colours. Like a moon phase it
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

// MARK: the night: deep space with slow clouds of the old night's colours and fine grain
[[ stitchable ]] half4 nightSpace(float2 position, half4 colour, float2 size, float t, float dark) {
    float2 uv = position / size.y;
    float3 navy = float3(0.075, 0.094, 0.165);
    float3 mauve = float3(0.33, 0.24, 0.36);
    float3 rose = float3(0.40, 0.25, 0.26);
    float3 deepTeal = float3(0.12, 0.24, 0.25);
    float n1 = fbm5(uv * 2.2 + float2(t * 0.004, -t * 0.003));
    float n2 = fbm5(uv * 1.7 + float2(-t * 0.003, t * 0.005) + 9.0);
    float n3 = fbm5(uv * 2.8 + 21.0);
    float3 col = navy;
    col = mix(col, mauve, smoothstep(0.42, 0.82, n1) * 0.8);
    col = mix(col, rose, smoothstep(0.5, 0.86, n2) * 0.7);
    col = mix(col, deepTeal, smoothstep(0.48, 0.85, n3) * 0.7);
    float grain = (h21(position * 0.9 + fract(t * 0.5)) - 0.5) * 0.035;
    col += grain;
    return half4(half3(col * dark), half(dark));
}

// MARK: THE SPACE MIST at full: thin nebula, the way it looks in real photographs: long wisps and filaments from
// twice-warped noise, a fine dust in them, very faint and nearly white, a breath of our blue and teal and a little rose
// where it is thickest. It spreads out from the sun as the sheet goes from p 0.3 to full: the field is drawn about the
// sun and scaled up from it, so it grows and moves and never fades in. Premultiplied, at most about a third covered:
// the map stays behind.
[[ stitchable ]] half4 spaceMist(float2 position, half4 colour, float2 size, float t, float p, float2 sun) {
    float e = smoothstep(0.3, 1.0, p);
    if (e <= 0.001) return half4(0);
    // the field's own coordinates, scaled out from the sun: at e it shows what it shows at full, e times as big round
    // the sun, so the wisps come out of the sun
    float2 f = (position - sun) / max(e, 0.05) / size.x;
    float2 drift = float2(t * 0.0025, -t * 0.0018);
    float2 w1 = float2(fbm5(f * 1.6 + drift), fbm5(f * 1.6 + float2(5.2, 1.3) - drift));
    float2 w2 = float2(fbm5(f * 2.2 + w1 * 2.2 + float2(1.7, 9.2)), fbm5(f * 2.2 + w1 * 2.2 + float2(8.3, 2.8)));
    float n = fbm5(f * 2.6 + w2 * 2.6);
    // filaments: the ridges of the warped field, thin and long
    float fil = ridged(f * 3.2 + w2 * 1.8 + drift * 2.0);
    float body = smoothstep(0.45, 0.85, n);
    float wisp = smoothstep(0.62, 0.95, fil) * smoothstep(0.35, 0.7, n);
    // dust: fine grains in the thick parts only
    float dust = smoothstep(0.8, 1.0, vn(position * 0.35 + 7.0)) * body * 0.5;
    // the field thins out towards the edge of the space it has reached
    float reachFade = 1.0 - smoothstep(0.55, 1.2, length((position - sun) / size.x) / max(e, 0.05));
    float dens = clamp(body * 0.55 + wisp * 0.7 + dust, 0.0, 1.0) * mix(0.35, 1.0, reachFade);
    float3 white = float3(1.0);
    float3 blue = float3(0.471, 0.682, 0.973), teal = float3(0.690, 0.878, 0.804), red = float3(0.851, 0.310, 0.239);
    float hue = fbm5(f * 0.9 + 13.0);
    float3 tint = mix(mix(blue, white, 0.55), mix(teal, white, 0.45), smoothstep(0.35, 0.65, hue));
    tint = mix(tint, mix(red, white, 0.72), smoothstep(0.6, 0.9, n) * 0.35);
    float3 col = mix(white, tint, 0.55 + 0.35 * body);
    // THE SPACE ITSELF: under the wisps a field of our blue deepening from the sun out to the screen's edges, so the
    // space reads as space and the white stars read on it; the wisps over it at twice their old weight
    float r = length((position - sun) / size.x) / max(e, 0.05);
    float3 deep = mix(blue, teal, smoothstep(0.3, 0.7, hue) * 0.35);
    float ga = 0.55 * smoothstep(0.08, 0.95, r);
    float wa = dens * 0.62;
    float a = wa + ga * (1.0 - wa);
    float3 c = (col * wa + deep * ga * (1.0 - wa)) / max(a, 0.0001);
    return half4(half3(c * a), half(a));
}
