const std = @import("std");
const zunkum = @import("zunkum");
const network = @import("network");

const Endpoints = @import("zchan/endpoints.zig");

const Post = @import("zchan/post.zig");

pub var posts: std.ArrayList(Post) = undefined;

pub fn main() !void {
    posts = std.ArrayList(Post).init(std.heap.c_allocator);
    defer posts.deinit();

    var server = try zunkum.create(std.heap.c_allocator, .{
        .middlewares = .{
            zunkum.Server.ServerMiddleware("zchan (zunkum)"),
            zunkum.Server.ContentTypeHtmlMiddleware,
            // zig fmt: off
            struct {
                var map = std.AutoHashMap(u32, i64).init(std.heap.c_allocator);
                
                pub fn handle(
                    request_context: *zunkum.Server.RequestContext,
                    response_context: *zunkum.Server.ResponseContext,
                ) !?std.http.Status {
                    _ = response_context;

                    //Only apply this to the `post` endpoint
                    if (!std.mem.eql(u8, request_context.path, "post")) return null;
                
                    //Get the address
                    const address = (try request_context.socket.getRemoteEndPoint()).address.ipv4.value;
                
                    //If we know of this address
                    if (map.get(@bitCast(address))) |lastTime| {
                        //If they posted less than 5 seconds ago
                        if (std.time.timestamp() - lastTime < 5) {
                            //Update the timestamp
                            try map.put(@bitCast(address), std.time.timestamp());
                            //Block the request
                            return .too_many_requests;
                        }
                    }

                    //Update the timestamp
                    try map.put(@bitCast(address), std.time.timestamp());
                
                    return null;
                }
            },
            //zig fmt: on
        },
        .services = .{
            struct {
                pub const Type = *std.ArrayList(Post);
                pub fn provide(request_context: *zunkum.Server.RequestContext) !Type {
                    _ = request_context;
                    return &posts;
                }
            },
        },
        .endpoint_groups = .{
            .{
                .endpoints = .{
                    .{
                        .path = "",
                        .fun = Endpoints.home,
                        .method = .GET,
                    },
                    .{
                        .path = "post",
                        .fun = Endpoints.post,
                        .method = .POST,
                    },
                },
            },
        },
    });
    try server.start();

    // try server.handleRequest("lbp/rate/{id}", &.{}, .POST);
    // try server.handleRequest("lbp/fake/{id}", &.{}, .POST);
    // try server.handleRequest("lbp/upload/hash/{hash}", &.{}, .GET);
}
