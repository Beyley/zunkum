const std = @import("std");
const network = @import("network");

const Endpoint = @import("endpoint.zig");

pub const RequestContext = struct {
    headers: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,
    version: std.http.Version,
    path: []const u8,
    method: std.http.Method,
};

pub const ResponseContext = struct {
    headers: std.StringHashMap([]const u8),
    body: ?[]const u8 = null,
};

pub fn ServerMiddleware(comptime name: []const u8) type {
    return struct {
        pub fn handle(request_context: *RequestContext, response_context: *ResponseContext) !void {
            _ = request_context;

            try response_context.headers.put("Server", name);
        }
    };
}

pub const Reader = std.io.BufferedReader(4096, network.Socket.Reader).Reader;
pub const Writer = std.io.BufferedWriter(4096, network.Socket.Writer).Writer;

pub fn Server(comptime init_args: anytype) type {
    return struct {
        comptime args: @TypeOf(init_args) = init_args,

        const Self = @This();

        pub fn start(self: *Self) !void {
            try network.init();
            defer network.deinit();

            var sock = try network.Socket.create(.ipv4, .tcp);
            defer sock.close();

            try sock.bindToPort(8080);

            try sock.listen();

            while (true) {
                var client = try sock.accept();
                defer client.close();

                var buffered_reader = std.io.bufferedReader(client.reader());
                var buffered_writer = std.io.bufferedWriter(client.writer());

                var reader = buffered_reader.reader();
                var writer = buffered_writer.writer();

                var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
                defer arena.deinit();

                const allocator = arena.allocator();

                var buf: [8196]u8 = undefined;

                var path_buf: [1024]u8 = undefined;

                var method = std.meta.stringToEnum(std.http.Method, try reader.readUntilDelimiter(&buf, ' ')).?;
                var path = try reader.readUntilDelimiter(&path_buf, ' ');
                var http_version = std.meta.stringToEnum(std.http.Version, try reader.readUntilDelimiter(&buf, '\r')).?;
                _ = try reader.readByte(); //read out the garbage \n :)

                var headers = std.StringHashMap([]const u8).init(allocator);
                defer headers.deinit();

                var header: []const u8 = undefined;
                while (blk: {
                    header = try reader.readUntilDelimiter(&buf, '\r');
                    _ = try reader.readByte();

                    break :blk header.len;
                } > 0) {
                    var iter = std.mem.splitSequence(u8, header, ":");

                    const key = std.mem.trim(u8, iter.next().?, &std.ascii.whitespace);
                    const value = std.mem.trim(u8, iter.next().?, &std.ascii.whitespace);

                    try headers.put(try allocator.dupe(u8, key), try allocator.dupe(u8, value));
                }

                var request_context = RequestContext{
                    .headers = headers,
                    .allocator = allocator,
                    .method = method,
                    .version = http_version,
                    .path = path[1..],
                };

                try self.handleRequest(
                    path[1..],
                    reader,
                    writer,
                    method,
                    &request_context,
                );
                try buffered_writer.flush();
            }
        }

        pub fn handleRequest(self: *Self, path: []const u8, reader: Reader, writer: Writer, method: std.http.Method, request_context: *RequestContext) !void {
            try self.processRequest(path, reader, writer, method, request_context);
        }

        pub fn processRequest(self: *Self, path: []const u8, reader: Reader, writer: Writer, method: std.http.Method, request_context: *RequestContext) !void {
            _ = reader;

            var response_context = ResponseContext{ .headers = std.StringHashMap([]const u8).init(request_context.allocator) };

            const middlewaresTypeInfo = @typeInfo(@TypeOf(init_args.middlewares)).Struct;

            inline for (middlewaresTypeInfo.fields) |field| {
                try @field(init_args.middlewares, field.name).handle(request_context, &response_context);
            }

            const path_hash = std.hash_map.hashString(path);

            const endpointGroupsType = @TypeOf(init_args.endpoint_groups);
            const endpointGroupsTypeInfo = @typeInfo(endpointGroupsType);

            inline for (endpointGroupsTypeInfo.Struct.fields) |field| {
                const endpoing_group_value = @field(init_args.endpoint_groups, field.name);
                const endpoint_prefix: []const u8 = endpoing_group_value.prefix;

                const endpointsTypeInfo = @typeInfo(@TypeOf(@field(endpoing_group_value, "endpoints")));

                inline for (endpointsTypeInfo.Struct.fields) |endpoint_field| {
                    const endpoint_value = @field(@field(endpoing_group_value, "endpoints"), endpoint_field.name);

                    const endpoint_path: []const u8 = endpoint_prefix ++ "/" ++ @field(endpoint_value, "path");
                    const endpoint_method: std.http.Method = @field(endpoint_value, "method");

                    if (endpoint_method == method and path_hash == comptime std.hash_map.hashString(endpoint_path)) {
                        const ArgsTuple = std.meta.ArgsTuple(@TypeOf(endpoint_value.fun));

                        var args: ArgsTuple = undefined;

                        const argsTypeInfo = @typeInfo(ArgsTuple);
                        loop: inline for (argsTypeInfo.Struct.fields) |args_field| {
                            if (args_field.type == RequestContext) {
                                @field(args, args_field.name) = request_context.*;
                                continue;
                            } else if (args_field.type == *RequestContext) {
                                @field(args, args_field.name) = response_context;
                                continue;
                            } else if (args_field.type == ResponseContext) {
                                @field(args, args_field.name) = response_context.*;
                                continue;
                            } else if (args_field.type == *ResponseContext) {
                                @field(args, args_field.name) = response_context;
                                continue;
                            }

                            const servicesTypeInfo = @typeInfo(@TypeOf(self.args.services)).Struct;

                            inline for (servicesTypeInfo.fields) |service_field| {
                                const service = @field(self.args.services, service_field.name);

                                if (args_field.type == service.Type) {
                                    @field(args, args_field.name) = try service.provide(request_context);
                                    continue :loop;
                                }
                            }

                            @compileError("No services handle param of type " ++ @typeName(args_field.type) ++ " on endpoint " ++ endpoint_path ++ "!");
                        }

                        var ret = @call(.auto, endpoint_value.fun, args) catch |err| {
                            try send_response(writer, request_context.*, response_context, .internal_server_error, err);

                            return;
                        };

                        try send_response(writer, request_context.*, response_context, ret, null);

                        return;
                    }
                }
            }

            try send_response(writer, request_context.*, response_context, .not_found, error.MissingEndpoint);
        }
    };
}

fn send_response(writer: Writer, request_context: RequestContext, response_context: ResponseContext, status_code: std.http.Status, err: ?anyerror) !void {
    //Write response version and response code
    try std.fmt.format(writer, "{s} {d} {s}\r\n", .{ @tagName(request_context.version), @intFromEnum(status_code), @tagName(status_code) });

    //Write headers
    var header_iter = response_context.headers.iterator();
    while (header_iter.next()) |header| {
        try std.fmt.format(writer, "{s}: {s}\r\n", .{ header.key_ptr.*, header.value_ptr.* });
    }
    try writer.writeAll("\r\n");

    //Write body
    if (err) |zig_error| {
        zig_error catch {};
        try std.fmt.format(writer, "<h1>{d} {s}!</h1><br><h3>error.{s}</h3>", .{ @intFromEnum(status_code), @tagName(status_code), @errorName(zig_error) });
    } else {
        if (response_context.body) |body| {
            try writer.writeAll(body);
        }
    }
}
