const std = @import("std");
const math = @import("math");

test "clamp" {
    std.debug.assert(math.clamp(5.0, 0.0, 10.0) == 5.0);
    std.debug.assert(math.clamp(-5.0, 0.0, 10.0) == 0.0);
    std.debug.assert(math.clamp(15.0, 0.0, 10.0) == 10.0);
    std.debug.assert(math.clamp(0.0, 0.0, 10.0) == 0.0);
    std.debug.assert(math.clamp(10.0, 0.0, 10.0) == 10.0);
}

test "lerp" {
    std.debug.assert(math.lerp(0.0, 10.0, 0.0) == 0.0);
    std.debug.assert(math.lerp(0.0, 10.0, 1.0) == 10.0);
    std.debug.assert(math.lerp(0.0, 10.0, 0.5) == 5.0);
    std.debug.assert(math.lerp(0.0, 10.0, 0.25) == 2.5);
    std.debug.assert(math.lerp(0.0, 10.0, -0.5) == 0.0); // 被clamp到0
    std.debug.assert(math.lerp(0.0, 10.0, 1.5) == 10.0); // 被clamp到1
}

test "distance" {
    std.debug.assert(math.approxEqual(math.distance(0.0, 0.0, 3.0, 4.0), 5.0, 0.001));
    std.debug.assert(math.approxEqual(math.distance(0.0, 0.0, 0.0, 0.0), 0.0, 0.001));
    std.debug.assert(math.approxEqual(math.distance(1.0, 1.0, 4.0, 5.0), 5.0, 0.001));
}

test "degToRad" {
    std.debug.assert(math.approxEqual(math.degToRad(0.0), 0.0, 0.001));
    std.debug.assert(math.approxEqual(math.degToRad(90.0), std.math.pi / 2.0, 0.001));
    std.debug.assert(math.approxEqual(math.degToRad(180.0), std.math.pi, 0.001));
    std.debug.assert(math.approxEqual(math.degToRad(360.0), 2.0 * std.math.pi, 0.001));
}

test "radToDeg" {
    std.debug.assert(math.approxEqual(math.radToDeg(0.0), 0.0, 0.001));
    std.debug.assert(math.approxEqual(math.radToDeg(std.math.pi / 2.0), 90.0, 0.001));
    std.debug.assert(math.approxEqual(math.radToDeg(std.math.pi), 180.0, 0.001));
    std.debug.assert(math.approxEqual(math.radToDeg(2.0 * std.math.pi), 360.0, 0.001));
}

test "approxEqual" {
    std.debug.assert(math.approxEqual(1.0, 1.0, 0.001));
    std.debug.assert(math.approxEqual(1.0, 1.0001, 0.001));
    std.debug.assert(!math.approxEqual(1.0, 1.01, 0.001));
    std.debug.assert(math.approxEqual(0.0, 0.0, 0.001));
    std.debug.assert(math.approxEqual(-1.0, -1.0, 0.001));
}

test "clamp edge cases" {
    std.debug.assert(math.clamp(5.0, 10.0, 0.0) == 10.0); // min > max的情况
    std.debug.assert(math.clamp(5.0, 5.0, 5.0) == 5.0); // min == max
}

test "lerp with negative values" {
    std.debug.assert(math.lerp(-10.0, 10.0, 0.0) == -10.0);
    std.debug.assert(math.lerp(-10.0, 10.0, 1.0) == 10.0);
    std.debug.assert(math.approxEqual(math.lerp(-10.0, 10.0, 0.5), 0.0, 0.001));
}

test "distance with negative coordinates" {
    std.debug.assert(math.approxEqual(math.distance(-1.0, -1.0, 2.0, 3.0), 5.0, 0.001));
    std.debug.assert(math.approxEqual(math.distance(-5.0, -5.0, -2.0, -1.0), 5.0, 0.001));
}
