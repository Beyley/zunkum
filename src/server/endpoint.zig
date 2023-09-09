const std = @import("std");

const Self = @This();

pub const EndpointMap = std.StringHashMap(Self);
pub const MethodEndpointMap = std.AutoHashMap(std.http.Method, EndpointMap);
