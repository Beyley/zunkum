const std = @import("std");
const network = @import("network");

pub const Server = @import("server/server.zig");
pub const Endpoint = @import("server/endpoint.zig");

pub fn create(allocator: std.mem.Allocator, comptime args: anytype) !*Server.Server(args) {
    const argsType: type = @TypeOf(args);

    if (!@hasField(argsType, "middlewares"))
        @compileError("Middlewares are not specified!");
    if (!@hasField(argsType, "services"))
        @compileError("Services are not specified!");
    if (!@hasField(argsType, "endpoint_groups"))
        @compileError("Endpoint groups are not specified");

    const server = try allocator.create(Server.Server(args));
    server.* = .{};

    return server;
}
