const std = @import("std");
const deancord = @import("deancord");

pub fn createPayRangeCommand(endpoint: *deancord.EndpointClient, application_id: deancord.model.Snowflake, guild_id: deancord.model.Snowflake) !deancord.model.Snowflake {
    const result = try endpoint.createGuildApplicationCommand(application_id, guild_id, deancord.EndpointClient.CreateGuildApplicationCommandBody{
        .default_permission = .{ .some = false },
        .default_member_permissions = .{ .some = deancord.model.Permissions{ .manage_messages = true, .create_private_threads = true } },
        .name = "include pay range",
        .type = .{ .some = .message },
    });
    defer result.deinit();
    switch (result.value()) {
        .ok => |command| return command.id,
        .err => |err| {
            std.log.err("error creating `include pay range` command: {}", .{std.json.fmt(err, .{})});
            return error.DiscordError;
        },
    }
}

pub fn handlePayRangeCommand(endpoint: *deancord.EndpointClient, event: deancord.gateway.event_data.receive_events.InteractionCreate) !void {
    const event_data = event.data.asSome() orelse return error.BadEvent;
    const application_command = switch (event_data) {
        .application_command => |cmd| cmd,
        else => return error.BadEvent,
    };

    const target_msg_id = application_command.target_id.asSome() orelse return error.NoTarget;
    var target_msg_id_str = std.BoundedArray(u8, 50){};
    try target_msg_id_str.writer().print("{s}", .{target_msg_id});
    const resolved_data = application_command.resolved.asSome() orelse return error.TargetNotResolved;
    const resolved_msgs = resolved_data.messages.asSome() orelse return error.TargetNotResolved;
    const target_msg: deancord.model.Message = resolved_msgs.map.get(target_msg_id_str.constSlice()) orelse return error.TargetNotResolved;

    const thread = event.channel.asSome() orelse {
        std.debug.print("event.channel null\n{}\n", .{std.json.fmt(event, .{})});
        try respondMustBeInThread(endpoint, event);
        return;
    };
    if (thread.partial.type.asSome() != .public_thread) {
        std.debug.print("type is not public_thread\n{}\n", .{std.json.fmt(thread, .{})});
        std.debug.print("type is not public_thread\n{?}\n", .{thread.partial.type.asSome()});
        try respondMustBeInThread(endpoint, event);
        return;
    }

    const owner_id = thread.partial.owner_id.asSome() orelse return error.MissingField;
    const thread_id = thread.partial.id.asSome() orelse return error.MissingField;

    // step 1: respond to thread
    try sendMessageInThread(endpoint, thread_id, owner_id, target_msg);

    // step 2: respond to command user
    try respondSuccess(endpoint, event);

    // step 3: close and lock thread
    const result = try endpoint.modifyChannel(thread_id, deancord.EndpointClient.ModifyChannelBody{
        .thread = .{
            .locked = .{ .some = true },
            .archived = .{ .some = true },
        },
    }, "did not include pay range");
    defer result.deinit();
    switch (result.value()) {
        .ok => {},
        .err => |discorderr| {
            std.log.err("error occurred while closing and locking thread: {}", .{std.json.fmt(discorderr, .{})});
            try respondError(endpoint, event);
        },
    }
}

fn respondMustBeInThread(endpoint: *deancord.EndpointClient, event: deancord.gateway.event_data.receive_events.InteractionCreate) !void {
    const result = try endpoint.createInteractionResponse(event.id, event.token, deancord.model.interaction.InteractionResponse{
        .type = .channel_message_with_source,
        .data = .{ .some = deancord.model.interaction.InteractionCallbackData{
            .allowed_mentions = .{ .some = deancord.model.Message.AllowedMentions{ .parse = &.{}, .replied_user = false, .roles = &.{}, .users = &.{} } },
            .content = .{ .some = "this command may only be used on messages contained in threads (i.e. forum posts)" },
            .flags = .{ .some = .{ .ephemeral = true } },
        } },
    });
    defer result.deinit();
    switch (result.value()) {
        .ok => {},
        .err => |discorderr| {
            std.log.err("error from discord during `respondMustBeInThread`: {}", .{std.json.fmt(discorderr, .{})});
            return error.DiscordError;
        },
    }
}
fn respondSuccess(endpoint: *deancord.EndpointClient, event: deancord.gateway.event_data.receive_events.InteractionCreate) !void {
    const result = try endpoint.createInteractionResponse(event.id, event.token, deancord.model.interaction.InteractionResponse{
        .type = .channel_message_with_source,
        .data = .{ .some = deancord.model.interaction.InteractionCallbackData{
            .allowed_mentions = .{ .some = deancord.model.Message.AllowedMentions{ .parse = &.{}, .replied_user = false, .roles = &.{}, .users = &.{} } },
            .content = .{ .some = "success" },
            .flags = .{ .some = .{ .ephemeral = true } },
        } },
    });
    defer result.deinit();
    switch (result.value()) {
        .ok => {},
        .err => |discorderr| {
            std.log.err("error from discord during `respondSuccess`: {}", .{std.json.fmt(discorderr, .{})});
            return error.DiscordError;
        },
    }
}
fn respondError(endpoint: *deancord.EndpointClient, event: deancord.gateway.event_data.receive_events.InteractionCreate) !void {
    const result = try endpoint.createInteractionResponse(event.id, event.token, deancord.model.interaction.InteractionResponse{
        .type = .channel_message_with_source,
        .data = .{ .some = deancord.model.interaction.InteractionCallbackData{
            .allowed_mentions = .{ .some = deancord.model.Message.AllowedMentions{ .parse = &.{}, .replied_user = false, .roles = &.{}, .users = &.{} } },
            .content = .{ .some = "some crazy error occurred" },
            .flags = .{ .some = .{ .ephemeral = true } },
        } },
    });
    defer result.deinit();
    switch (result.value()) {
        .ok => {},
        .err => |discorderr| {
            std.log.err("error from discord during `respondSuccess`: {}", .{std.json.fmt(discorderr, .{})});
            return error.DiscordError;
        },
    }
}

fn sendMessageInThread(endpoint: *deancord.EndpointClient, thread_id: deancord.model.Snowflake, owner_id: deancord.model.Snowflake, message: deancord.model.Message) !void {
    var content = std.BoundedArray(u8, 4000){};
    try content.writer().print(pay_range_fmt, .{owner_id});

    const result = try endpoint.createMessage(thread_id, deancord.EndpointClient.CreateMessageFormBody{
        .allowed_mentions = .{ .replied_user = false, .users = &.{owner_id}, .parse = &.{}, .roles = &.{} },
        .content = content.constSlice(),
        .message_reference = deancord.model.Message.Reference{
            .fail_if_not_exists = .{ .some = false },
            .message_id = .{ .some = message.id },
        },
    });
    defer result.deinit();
    switch (result.value()) {
        .ok => {},
        .err => |discorderr| {
            std.log.err("error from discord during `respondSuccess`: {}", .{std.json.fmt(discorderr, .{})});
            return error.DiscordError;
        },
    }
}

const pay_range_fmt =
    \\<@{}>, please include a pay range in your post. While a specific pay amount is not needed, it is important for people to know at least a ballpark estimate of how much money they will be making.
    \\
    \\Examples can still be vague, even something like '100 to 1000 dollars per project, depending on size' is fine. However, you must be more specific than just 'contact me for pay info' or 'pay depends on experience'.
;
