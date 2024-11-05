const std = @import("std");
const RetryTimer = @This();

timer: std.time.Timer,
current_retries: u32,

max_retries: u32,
cooldown_ns: u64,

pub fn init(max_retries: u32, cooldown_ns: u64) RetryTimer {
    return RetryTimer{
        .timer = std.time.Timer.start() catch std.debug.panic("timer not available", .{}),
        .current_retries = 0,
        .max_retries = max_retries,
        .cooldown_ns = cooldown_ns,
    };
}

pub fn retry(self: *RetryTimer) bool {
    if (self.timer.read() > self.cooldown_ns) {
        self.timer.reset();
        self.current_retries = 0;
    }

    self.current_retries += 1;
    if (self.current_retries > self.max_retries) {
        return false;
    }
    return true;
}

test {
    var timer = RetryTimer.init(20, 10 * std.time.ns_per_s);

    var tries: u32 = 0;
    while (tries < 20) : (tries += 1) {
        try std.testing.expect(timer.retry());
    }

    try std.testing.expect(!timer.retry());
}
