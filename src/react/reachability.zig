const std = @import("std");
const parser = @import("parser.zig");

const Allocator = std.mem.Allocator;

fn addReachableIndex(
    queue: *std.ArrayList(usize),
    seen: *std.AutoHashMap(usize, void),
    index: usize,
) !void {
    const entry = try seen.getOrPut(index);
    if (entry.found_existing) return;
    try queue.append(index);
}

pub fn collectReachableComponents(allocator: Allocator, components: []const parser.Component) ![]parser.Component {
    var reachable = std.ArrayList(parser.Component).init(allocator);
    errdefer reachable.deinit();

    if (components.len == 0) return try reachable.toOwnedSlice();

    var by_name = std.StringHashMap(usize).init(allocator);
    defer by_name.deinit();
    for (components, 0..) |component, idx| {
        if (!by_name.contains(component.name)) try by_name.put(component.name, idx);
    }

    var queue = std.ArrayList(usize).init(allocator);
    defer queue.deinit();

    var seen = std.AutoHashMap(usize, void).init(allocator);
    defer seen.deinit();

    try addReachableIndex(&queue, &seen, 0);

    var cursor: usize = 0;
    while (cursor < queue.items.len) : (cursor += 1) {
        const component = components[queue.items[cursor]];
        try reachable.append(component);

        for (component.route_pages) |page| {
            if (by_name.get(page.component)) |child_idx| {
                try addReachableIndex(&queue, &seen, child_idx);
            }
        }

        for (component.dom_nodes) |node| {
            if (!node.is_user_component) continue;
            if (by_name.get(node.tag)) |child_idx| {
                try addReachableIndex(&queue, &seen, child_idx);
            }
        }
    }

    return try reachable.toOwnedSlice();
}

test "collectReachableComponents follows user components and routes" {
    const source =
        \\<Component name="App">
        \\  <Router>
        \\    <Page path="/about" component="AboutPage" />
        \\  </Router>
        \\</Component>
        \\<Component name="Unused">
        \\  <div>Unused</div>
        \\</Component>
        \\<Component name="AboutPage">
        \\  <Shell />
        \\</Component>
        \\<Component name="Shell">
        \\  <AboutWidget />
        \\</Component>
        \\<Component name="AboutWidget">
        \\  <span>Widget</span>
        \\</Component>
    ;

    var sax_parser = parser.SaxParser.init(std.testing.allocator, source);
    var program = try sax_parser.parse();
    defer program.deinit();

    const reachable = try collectReachableComponents(std.testing.allocator, program.components);
    defer std.testing.allocator.free(reachable);

    try std.testing.expectEqual(@as(usize, 4), reachable.len);
    try std.testing.expectEqualStrings("App", reachable[0].name);
    try std.testing.expectEqualStrings("AboutPage", reachable[1].name);
    try std.testing.expectEqualStrings("Shell", reachable[2].name);
    try std.testing.expectEqualStrings("AboutWidget", reachable[3].name);
}
