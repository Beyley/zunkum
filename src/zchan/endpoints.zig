const std = @import("std");
const zunkum = @import("zunkum");

const Post = @import("post.zig");

pub fn home(
    request_context: zunkum.Server.RequestContext,
    response_context: *zunkum.Server.ResponseContext,
    posts: *std.ArrayList(Post),
) !std.http.Status {
    var response_body = std.ArrayList(u8).init(request_context.allocator);
    try response_body.ensureTotalCapacity(1000 + @embedFile("form.html").len + @embedFile("submit.js").len);

    try response_body.appendSlice(
        \\<!DOCTYPE html>
        \\<div class="center"><h1>zchan</h1></div>
    );

    try response_body.appendSlice("<style>" ++ @embedFile("style.css") ++ "</style>");

    try response_body.appendSlice("<script>" ++ @embedFile("submit.js") ++ "</script>");
    try response_body.appendSlice(@embedFile("form.html"));

    try response_body.appendSlice("<hr>");

    var i: usize = 0;
    while (i < @min(50, posts.items.len)) : (i += 1) {
        const post_item = posts.items[posts.items.len - i - 1];

        try response_body.appendSlice("<p>");
        try std.fmt.format(response_body.writer(), "<h2>{s}</h2>", .{post_item.name.slice()});
        for (post_item.content.slice()) |c| {
            switch (c) {
                '&' => try response_body.appendSlice("&amp;"),
                '<' => try response_body.appendSlice("&lt;"),
                '>' => try response_body.appendSlice("&gt;"),
                '"' => try response_body.appendSlice("&quot;"),
                '\'' => try response_body.appendSlice("&#39;"),
                '\n' => try response_body.appendSlice("<br>"),
                else => try response_body.append(c),
            }
        }
        try response_body.appendSlice("</p><hr>");
    }

    response_context.body = try response_body.toOwnedSlice();
    return .ok;
}

pub fn post(
    request_context: zunkum.Server.RequestContext,
    posts: *std.ArrayList(Post),
    reader: zunkum.Server.Reader,
) !std.http.Status {
    if (request_context.headers.get("Content-Length") == null) {
        return .bad_request;
    }

    //TODO: figure out how to not alloc here
    var body = try request_context.allocator.alloc(u8, try std.fmt.parseInt(usize, request_context.headers.get("Content-Length").?, 10));
    const read = try reader.read(body);

    const NetworkPost = struct {
        name: []const u8,
        content: []const u8,
    };

    const post_from_network = try std.json.parseFromSliceLeaky(NetworkPost, request_context.allocator, body[0..read], .{});

    if (post_from_network.content.len == 0) {
        return .bad_request;
    }

    if (!std.unicode.utf8ValidateSlice(post_from_network.content) or !std.unicode.utf8ValidateSlice(post_from_network.name)) {
        return .bad_request;
    }

    try posts.append(.{
        .name = try std.BoundedArray(u8, 128).fromSlice(post_from_network.name),
        .content = try std.BoundedArray(u8, 4096).fromSlice(post_from_network.content),
    });

    return .ok;
}
