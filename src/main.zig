const std = @import("std");
const zunkum = @import("zunkum");

// fn upload(context: RequestContext, database: DatabaseContext) !void {
fn upload(request_context: zunkum.Server.RequestContext) !std.http.Status {
    var iter = request_context.headers.iterator();
    _ = iter;

    return error.Shit;
    // return .bad_request;
}

// fn rate(context: RequestContext, database: DatabaseContext) !void {
fn rate() !std.http.Status {
    // return error.SHIT;
    return .ok;
}

pub fn main() !void {
    var server = try zunkum.create(std.heap.c_allocator, .{
        .middlewares = .{
            zunkum.Server.ServerMiddleware("zunkum test"),
        },
        .services = .{
            struct {
                pub const Type = std.http.Version;
                pub fn provide(request_context: *zunkum.Server.RequestContext) !Type {
                    _ = request_context;
                    return std.http.Version.@"HTTP/1.0";
                }
            },
        },
        .endpoint_groups = .{
            .{
                .prefix = "lbp",
                .endpoints = .{
                    .{
                        .path = "upload/hash/",
                        .fun = upload,
                        .method = .GET,
                    },
                    .{
                        .path = "rate/",
                        .fun = rate,
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
