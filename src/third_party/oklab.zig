// Copyright (c) 2020 Björn Ottosson
// Permission is hereby granted, free of charge, to any person obtaining a copy of
// this software and associated documentation files (the "Software"), to deal in
// the Software without restriction, including without limitation the rights to
// use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is furnished to do
// so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// https://bottosson.github.io/posts/oklab/

// struct Lab {float L; float a; float b;};
// struct RGB {float r; float g; float b;};

// Lab linear_srgb_to_oklab(RGB c)
// {
//  float l = 0.4122214708f * c.r + 0.5363325363f * c.g + 0.0514459929f * c.b;
//  float m = 0.2119034982f * c.r + 0.6806995451f * c.g + 0.1073969566f * c.b;
//  float s = 0.0883024619f * c.r + 0.2817188376f * c.g + 0.6299787005f * c.b;

//     // pierwiastek sześcienny z math.h from stdlib since c99
//     float l_ = cbrtf(l);
//     float m_ = cbrtf(m);
//     float s_ = cbrtf(s);

//     return {
//         0.2104542553f*l_ + 0.7936177850f*m_ - 0.0040720468f*s_,
//         1.9779984951f*l_ - 2.4285922050f*m_ + 0.4505937099f*s_,
//         0.0259040371f*l_ + 0.7827717662f*m_ - 0.8086757660f*s_,
//     };
// }

// RGB oklab_to_linear_srgb(Lab c)
// {
//     float l_ = c.L + 0.3963377774f * c.a + 0.2158037573f * c.b;
//     float m_ = c.L - 0.1055613458f * c.a - 0.0638541728f * c.b;
//     float s_ = c.L - 0.0894841775f * c.a - 1.2914855480f * c.b;

//     float l = l_*l_*l_;
//     float m = m_*m_*m_;
//     float s = s_*s_*s_;

//     return {
//      +4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s,
//      -1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s,
//      -0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s,
//     };
// }

const std = @import("std");
const m = @import("../math.zig");

pub fn srgb_to_oklab(srgb: m.vec3) m.vec3 {
    const lms_conv: [3]m.vec3 = .{
        .{ 0.4122214708, 0.5363325363, 0.0514459929 },
        .{ 0.2119034982, 0.6806995451, 0.1073969566 },
        .{ 0.0883024619, 0.2817188376, 0.6299787005 },
    };
    var lms: m.vec3 = undefined;
    for (0..3) |i| lms[i] = m.dot(lms_conv[i], srgb);
    std.debug.print("+++ before root {}\n", .{lms});
    for (0..3) |i| lms[i] = std.math.cbrt(lms[i]);
    std.debug.print("+++ after root {}\n", .{lms});

    const lab_conv: [3]m.vec3 = .{
        .{ 0.2104542553, 0.7936177850, -0.0040720468 },
        .{ 1.9779984951, -2.4285922050, 0.4505937099 },
        .{ 0.0259040371, 0.7827717662, -0.8086757660 },
    };
    var lab: m.vec3 = undefined;
    for (0..3) |i| lab[i] = m.dot(lab_conv[i], lms);

    return lab;
}

pub fn oklab_to_srgb(lab: m.vec3) m.vec3 {
    const lms_conv: [3]m.vec3 = .{
        .{ 1, 0.3963377774, 0.2158037573 },
        .{ 1, -0.1055613458, -0.0638541728 },
        .{ 1, -0.0894841775, -1.2914855480 },
    };

    var lms: m.vec3 = undefined;
    for (0..3) |i| lms[i] = m.dot(lms_conv[i], lab);
    for (0..3) |i| lms[i] = lms[i] * lms[i] * lms[i];

    const srgb_conv: [3]m.vec3 = .{
        .{ 4.0767416621, -3.3077115913, 0.2309699292 },
        .{ -1.2684380046, 2.6097574011, -0.3413193965 },
        .{ -0.0041960863, -0.7034186147, 1.7076147010 },
    };

    var srgb: m.vec3 = undefined;
    for (0..3) |i| srgb[i] = m.dot(srgb_conv[i], lms);
    return srgb;
}
