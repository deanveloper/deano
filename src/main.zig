const std = @import("std");
const deancord = @import("deancord");
const interactions = @import("./interactions.zig");
const RetryTimer = @import("./RetryTimer.zig");

test {
    _ = interactions;
    _ = RetryTimer;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const token = try getenvOwned(allocator, "TOKEN");
    defer allocator.free(token);
    const guild_id = blk: {
        const guild = try getenvOwned(allocator, "GUILD");
        defer allocator.free(guild);
        const id = std.fmt.parseInt(u64, guild, 10) catch {
            std.log.err("GUILD env var must be an integer", .{});
            return;
        };
        break :blk deancord.model.Snowflake.fromU64(id);
    };

    const auth = deancord.Authorization{ .bot = token };

    var endpoint = deancord.EndpointClient.init(allocator, auth);
    defer endpoint.deinit();

    var retry_timer = RetryTimer.init(5, 10 * std.time.ns_per_s);
    while (retry_timer.retry()) {
        startBot(allocator, &endpoint, token, guild_id) catch |err| {
            std.log.err("==== UH OH!! ====", .{});
            std.log.err("error returned in gateway: {}", .{err});
            if (@errorReturnTrace()) |trace| {
                std.log.err("{}", .{trace});
            }
        };
    }

    std.log.err("Hit 5 retries within 10 seconds, aborting", .{});
}

fn startBot(allocator: std.mem.Allocator, endpoint: *deancord.EndpointClient, token: []const u8, guild_id: deancord.model.Snowflake) !void {
    var gateway = try deancord.GatewayClient.initWithRestClient(allocator, endpoint);
    errdefer gateway.deinit();

    const application_id = try initializeBot(&gateway, token);

    destroyAllCommands(endpoint, application_id);

    const pay_range_cmd = try interactions.createPayRangeCommand(endpoint, application_id, guild_id);

    while (true) {
        const parsed = gateway.readEvent() catch |err| switch (err) {
            error.EndOfStream, error.ServerClosed => return err,
            else => {
                std.log.err("error occurred while reading gateway event: {}", .{err});
                continue;
            },
        };
        defer parsed.deinit();

        switch (parsed.value.d orelse continue) {
            .InteractionCreate => |interaction_create| {
                switch (interaction_create.data.asSome() orelse continue) {
                    .application_command => |command| {
                        if (command.id.asU64() == pay_range_cmd.asU64()) {
                            interactions.handlePayRangeCommand(endpoint, interaction_create) catch |err| {
                                std.log.err("error occurred during handlePayRangeCommand: {}", .{err});
                                if (@errorReturnTrace()) |trace| {
                                    std.log.err("{}", .{trace});
                                }
                                continue;
                            };
                        } else {
                            std.log.warn("unknown command id: '{}' (our command is id '{}')", .{ interaction_create.id, pay_range_cmd });
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }
    }
}

fn initializeBot(
    gateway: *deancord.GatewayClient,
    token: []const u8,
) !deancord.model.Snowflake {
    const ready_parsed = try gateway.authenticate(token, deancord.model.Intents{});
    defer ready_parsed.deinit();

    const event = ready_parsed.value.d orelse {
        std.log.err("data value of ready event not found", .{});
        return error.BadReadyEvent;
    };
    switch (event) {
        .Ready => |ready| {
            std.log.info("authenticated as user {}", .{ready.user.id});
            return ready.application.id;
        },
        else => |other_event| {
            std.log.err("expected ready event, got {s}", .{@tagName(other_event)});
            return error.BadReadyEvent;
        },
    }
}
fn destroyAllCommands(client: *deancord.EndpointClient, application_id: deancord.model.Snowflake) void {
    const get_cmds_result = client.getGlobalApplicationCommands(application_id, null) catch |err| {
        std.log.err("error while listing commands: {}", .{err});
        return;
    };
    defer get_cmds_result.deinit();
    const commands = switch (get_cmds_result.value()) {
        .ok => |cmds| cmds,
        .err => |err| {
            std.log.err("error from discord while listing commands: {}", .{err});
            return;
        },
    };

    for (commands) |command| {
        std.log.info("destroying command '{s}'", .{command.name});
        const delete_cmd_result = client.deleteGlobalApplicationCommand(application_id, command.id) catch |err| {
            std.log.err("error deleting command '{s}': {}", .{ command.name, err });
            return;
        };
        switch (delete_cmd_result.value()) {
            .ok => {},
            .err => |err| {
                std.log.err("error from discord while deleting command '{s}': {}", .{ command.name, err });
                return;
            },
        }
    }
}
fn getenvOwned(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const token = std.process.getEnvVarOwned(allocator, name) catch |err| {
        switch (err) {
            error.EnvironmentVariableNotFound => {
                std.log.err("environment variable {s} is required", .{name});
                return err;
            },
            else => return err,
        }
    };
    return token;
}
