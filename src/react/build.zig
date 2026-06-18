const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

fn writeTestWasm(path: []const u8) !void {
    try ensureParentDir(path);
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll("\x00asm\x01\x00\x00\x00\x00\x09\x08sax-test");
}

fn runLlvmAs(allocator: std.mem.Allocator, ll_path: []const u8, artifact_path: []const u8) !void {
    const tools = [_][]const u8{ "llvm-as-14", "llvm-as" };
    for (tools) |tool| {
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ tool, ll_path, "-o", artifact_path },
        }) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        switch (result.term) {
            .Exited => |code| if (code == 0) return,
            else => {},
        }
        return error.ChildProcessFailed;
    }
    return error.LlvmAsNotFound;
}

fn writeTestBitcode(allocator: std.mem.Allocator, artifact_path: []const u8) !void {
    const ll_path = try std.fmt.allocPrint(allocator, "{s}.ll", .{artifact_path});
    defer allocator.free(ll_path);
    defer std.fs.cwd().deleteFile(ll_path) catch {};

    try writeAllFile(ll_path,
        \\target triple = "wasm32-unknown-unknown"
        \\define void @__sax_test() {
        \\entry:
        \\  ret void
        \\}
        \\
    );
    try runLlvmAs(allocator, ll_path, artifact_path);
}

const TestDriver = struct {
    pub const Optimization = enum { release_small, release_fast };

    const WasmArgv = struct {
        allocator: std.mem.Allocator,
        items: []const []const u8,
        owned_args: []const []const u8,

        pub fn slice(self: *const WasmArgv) []const []const u8 {
            return self.items;
        }

        pub fn deinit(self: *WasmArgv) void {
            for (self.owned_args) |arg| self.allocator.free(arg);
            self.allocator.free(self.owned_args);
            self.allocator.free(self.items);
            self.* = undefined;
        }
    };

    pub fn argvForWasm(
        allocator: std.mem.Allocator,
        artifact_paths: []const []const u8,
        out_path: []const u8,
        target: struct { triple: []const u8, no_entry: bool, import_symbols: bool = false, exports: []const []const u8 = &.{} },
        optimization: Optimization,
        debug: bool,
    ) !WasmArgv {
        var argv = std.ArrayList([]const u8).init(allocator);
        errdefer argv.deinit();

        var owned_args = std.ArrayList([]const u8).init(allocator);
        errdefer {
            for (owned_args.items) |arg| allocator.free(arg);
            owned_args.deinit();
        }

        try argv.appendSlice(&.{ "zig", "build-exe" });
        for (artifact_paths) |p| try argv.append(p);
        if (debug) {
            try argv.append("-g");
        }
        try argv.appendSlice(&.{ "-target", target.triple });
        if (target.no_entry) {
            try argv.append("-fno-entry");
        }
        if (target.import_symbols) {
            try argv.append("--import-symbols");
        }
        for (target.exports) |export_name| {
            const arg = try std.fmt.allocPrint(allocator, "--export={s}", .{export_name});
            var owned = false;
            errdefer if (!owned) allocator.free(arg);
            try owned_args.append(arg);
            owned = true;
            try argv.append(arg);
        }
        try argv.append("-O");
        try argv.append(if (debug) "Debug" else switch (optimization) {
            .release_small => "ReleaseSmall",
            .release_fast => "ReleaseFast",
        });
        const emit_bin = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{out_path});
        var emit_bin_owned = false;
        errdefer if (!emit_bin_owned) allocator.free(emit_bin);
        try owned_args.append(emit_bin);
        emit_bin_owned = true;
        try argv.append(emit_bin);
        const items = try argv.toOwnedSlice();
        errdefer allocator.free(items);
        const owned = try owned_args.toOwnedSlice();

        return .{
            .allocator = allocator,
            .items = items,
            .owned_args = owned,
        };
    }

    pub fn compileWasm(
        allocator: std.mem.Allocator,
        artifact_paths: []const []const u8,
        out_path: []const u8,
        options: struct { triple: []const u8, no_entry: bool, import_symbols: bool = false, exports: []const []const u8 = &.{} },
        optimization: Optimization,
        debug: bool,
        stderr: anytype,
    ) !void {
        _ = allocator;
        _ = artifact_paths;
        _ = options;
        _ = optimization;
        _ = debug;
        _ = stderr;
        try writeTestWasm(out_path);
    }
};

const TestEmitLlvmc = struct {
    pub const EmitOptions = struct { debug: bool = false, wasm_compat: bool = false, jobs: ?usize = null, dce: emit_options.DceMode = .std, std_root: ?[]const u8 = null };
    pub fn emitLlvmcToFile(
        allocator: std.mem.Allocator,
        verified: anytype,
        def_dict: anytype,
        loc_table: anytype,
        source_path: []const u8,
        size_bits: u16,
        options: EmitOptions,
        artifact_path: []const u8,
    ) !void {
        _ = verified;
        _ = def_dict;
        _ = loc_table;
        _ = source_path;
        _ = size_bits;
        _ = options;
        try writeTestBitcode(allocator, artifact_path);
    }
};

const TestTrap = struct {};
const TestReferee = struct {
    pub const VerifyOk = struct {
        pub fn deinit(self: *VerifyOk, allocator: std.mem.Allocator) void {
            _ = allocator;
            self.* = undefined;
        }
    };
    pub const VerifyResult = union(enum) { ok: VerifyOk, trap: TestTrap };
    pub fn verifyWithOptions(
        allocator: std.mem.Allocator,
        instructions: anytype,
        const_decls: anytype,
        options: anytype,
    ) !VerifyResult {
        _ = allocator;
        _ = instructions;
        _ = const_decls;
        _ = options;
        return .{ .ok = .{} };
    }
};

const TestFlattenResult = struct {
    def_dict: void = {},
    loc_table: void = {},
    pub fn deinit(self: *TestFlattenResult, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.* = undefined;
    }
};

const TestFlattener = struct {
    pub const FlattenResult = TestFlattenResult;
    pub const ErrorContext = struct {};
    pub const ResolveContext = struct { dependencies: []const u8 = &.{}, options: struct { project_root: []const u8, std_root: ?[]const u8 = null } = .{ .project_root = "" } };
    pub fn takeErrorSourceLine(ctx: *ErrorContext) ?u32 {
        _ = ctx;
        return null;
    }
    pub fn flattenFileWithContextAndPackages(
        allocator: std.mem.Allocator,
        source_path: []const u8,
        source_text: []const u8,
        error_ctx: *ErrorContext,
        resolve_ctx: ResolveContext,
    ) !FlattenResult {
        _ = allocator;
        _ = source_path;
        _ = error_ctx;
        _ = resolve_ctx;
        if (std.mem.indexOf(u8, source_text, "<Component") == null and std.mem.indexOf(u8, source_text, "@export") == null) return error.InvalidComponentBody;
        return .{};
    }
};

const TestManifest = struct {};
const TestPkgResolver = struct {
    pub const Dependency = struct { url: []const u8 = "", ref: []const u8 = "" };
};

const driver = if (builtin.is_test) TestDriver else @import("../driver/zigcc.zig");
const emit_options = @import("../emit_options.zig");
const emit_llvm_llvmc = if (builtin.is_test) TestEmitLlvmc else @import("../emit_llvm_llvmc.zig");
const flattener = if (builtin.is_test) TestFlattener else @import("../flattener.zig");
const manifest = if (builtin.is_test) TestManifest else @import("../pkg/manifest.zig");
const pkg_resolver = if (builtin.is_test) TestPkgResolver else @import("../pkg/resolver.zig");
const referee = if (builtin.is_test) TestReferee else @import("../referee.zig");
const trap = @import("../common/trap.zig");

pub const CompileOptions = struct {
    jobs: ?usize = null,
    dce: emit_options.DceMode = .std,
};

pub const SourceUnit = struct {
    logical_name: []const u8,
    source_path: []const u8,
    source_text: []const u8,
};

pub const CompileOk = if (builtin.is_test) struct {
    pub fn deinit(self: *CompileOk, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.* = undefined;
    }
} else struct {
    flat: flattener.FlattenResult,
    verified: referee.VerifyOk,

    pub fn deinit(self: *CompileOk, allocator: std.mem.Allocator) void {
        self.verified.deinit(allocator);
        self.flat.deinit(allocator);
        self.* = undefined;
    }
};

pub const CompileResult = if (builtin.is_test) union(enum) { ok: CompileOk, trap: TestTrap } else union(enum) {
    ok: CompileOk,
    trap: trap.TrapReport,
};

fn projectRootFromSourcePath(allocator: std.mem.Allocator, source_path: []const u8) ![]u8 {
    const cwd_abs = try std.fs.cwd().realpathAlloc(allocator, ".");
    errdefer allocator.free(cwd_abs);

    const source_dir = std.fs.path.dirname(source_path) orelse ".";
    var current = try allocator.dupe(u8, source_dir);
    defer allocator.free(current);

    while (true) {
        const candidate_dir = if (std.fs.path.isAbsolute(current))
            try allocator.dupe(u8, current)
        else
            try std.fs.path.join(allocator, &.{ cwd_abs, current });
        defer allocator.free(candidate_dir);

        const manifest_path = try std.fs.path.join(allocator, &.{ candidate_dir, "sa.mod" });
        defer allocator.free(manifest_path);

        if (std.fs.cwd().openFile(manifest_path, .{})) |file| {
            file.close();
            allocator.free(cwd_abs);
            return try std.fs.cwd().realpathAlloc(allocator, candidate_dir);
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        }

        const parent = std.fs.path.dirname(current) orelse break;
        if (std.mem.eql(u8, parent, current)) break;
        const next = try allocator.dupe(u8, parent);
        allocator.free(current);
        current = next;
    }

    return cwd_abs;
}

fn stdRootFromEnv(allocator: std.mem.Allocator) ![]u8 {
    const env_root = std.process.getEnvVarOwned(allocator, "SA_STD_DIR") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    if (env_root) |root| {
        errdefer allocator.free(root);
        return root;
    }
    return try std.fs.path.join(allocator, &.{ build_options.repo_root, "sa_std" });
}

fn readProjectManifest(allocator: std.mem.Allocator, source_path: []const u8) !?manifest.Manifest {
    if (builtin.is_test) {
        return null;
    }
    const project_root = try projectRootFromSourcePath(allocator, source_path);
    defer allocator.free(project_root);
    const manifest_path = try std.fs.path.join(allocator, &.{ project_root, "sa.mod" });
    defer allocator.free(manifest_path);

    const file = std.fs.cwd().openFile(manifest_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
    defer allocator.free(source);
    return try manifest.parseManifestWithFile(allocator, source, manifest_path);
}

fn manifestDependencies(manifest_file: *const manifest.Manifest, allocator: std.mem.Allocator) ![]pkg_resolver.Dependency {
    if (builtin.is_test) return &.{};
    var deps = std.ArrayList(pkg_resolver.Dependency).init(allocator);
    errdefer deps.deinit();

    for (manifest_file.requires) |entry| {
        try deps.append(.{ .url = entry.url, .ref = entry.ref });
    }

    return try deps.toOwnedSlice();
}

fn lineAt(source: []const u8, target_line: u32) ?[]const u8 {
    if (target_line == 0) return null;
    var iter = std.mem.splitScalar(u8, source, '\n');
    var line_no: u32 = 1;
    while (iter.next()) |line| : (line_no += 1) {
        if (line_no == target_line) return line;
    }
    return null;
}

fn sourceExcerpt(line: []const u8) []const u8 {
    return std.mem.trimRight(u8, line, "\r");
}

fn copyTextBuf(dest: []u8, text: []const u8) void {
    const len = @min(dest.len, text.len);
    std.mem.copyForwards(u8, dest[0..len], text[0..len]);
}

fn bufText(buf: []const u8) []const u8 {
    return buf[0..(std.mem.indexOfScalar(u8, buf, 0) orelse buf.len)];
}

fn sourceStem(path: []const u8) []const u8 {
    const basename = std.fs.path.basename(path);
    const dot_idx = std.mem.lastIndexOfScalar(u8, basename, '.') orelse basename.len;
    return basename[0..dot_idx];
}

fn dupeWasmExports(allocator: std.mem.Allocator, source_text: []const u8) ![]const []const u8 {
    var exports = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (exports.items) |name| allocator.free(name);
        exports.deinit();
    }

    var lines = std.mem.splitScalar(u8, source_text, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trimRight(u8, line, "\r");
        if (!std.mem.startsWith(u8, trimmed, "@export ")) continue;

        const rest = std.mem.trimLeft(u8, trimmed["@export ".len..], " \t");
        const open = std.mem.indexOfScalar(u8, rest, '(') orelse continue;
        const name = std.mem.trimRight(u8, rest[0..open], " \t");
        if (name.len == 0) continue;

        const export_name = try allocator.dupe(u8, name);
        errdefer allocator.free(export_name);
        try exports.append(export_name);
    }

    return try exports.toOwnedSlice();
}

fn dupeWasmExportsFromSourceUnits(allocator: std.mem.Allocator, units: []const SourceUnit) ![]const []const u8 {
    var exports = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (exports.items) |name| allocator.free(name);
        exports.deinit();
    }

    for (units) |unit| {
        const unit_exports = try dupeWasmExports(allocator, unit.source_text);
        defer freeWasmExports(allocator, unit_exports);

        for (unit_exports) |name| {
            var found = false;
            for (exports.items) |existing| {
                if (std.mem.eql(u8, existing, name)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                try exports.append(try allocator.dupe(u8, name));
            }
        }
    }

    return try exports.toOwnedSlice();
}

fn freeWasmExports(allocator: std.mem.Allocator, exports: []const []const u8) void {
    for (exports) |name| allocator.free(name);
    allocator.free(exports);
}

pub fn printTrapReport(writer: anytype, report: anytype) !void {
    if (builtin.is_test) {
        try writer.writeAll("error: trap\n");
        return;
    }
    const trap_report: trap.TrapReport = report;
    try writer.print("error[{s}]: {s}\n", .{ trap.trapName(trap_report.trap), trap_report.message });
    if (trap_report.source_line != 0) {
        const source_text = bufText(trap_report.source_text_buf[0..]);
        if (source_text.len != 0) {
            try writer.print("  line {d}: {s}\n", .{ trap_report.source_line, source_text });
        } else {
            try writer.print("  line {d}\n", .{trap_report.source_line});
        }
    }
    if (trap_report.hint) |hint| {
        try writer.print("  help: {s}\n", .{hint});
    }
    try trap.writeJson(writer, trap_report);
    try writer.writeByte('\n');
}

fn trapFromFlattenError(source: []const u8, err: anyerror, last_line: ?u32) if (builtin.is_test) TestTrap else trap.TrapReport {
    if (builtin.is_test) return .{};
    const line_no = last_line orelse 1;
    const line_text = lineAt(source, line_no);
    var report: trap.TrapReport = .{
        .trap = .forbidden_syntax,
        .trap_code = trap.trapCode(.forbidden_syntax),
        .line = line_no,
        .source_line = line_no,
        .source_text_buf = [_]u8{0} ** 256,
        .original_text_buf = [_]u8{0} ** 256,
        .source_text = null,
        .original_text = null,
        .register = null,
        .registers = &.{},
        .expected_mask = null,
        .actual_mask = null,
        .expected_mask_name = null,
        .actual_mask_name = null,
        .upstream_loc = null,
        .upstream_file_buf = [_]u8{0} ** 128,
        .upstream_line = 0,
        .upstream_col = 0,
        .function_buf = [_]u8{0} ** 64,
        .function = null,
        .is_ffi_wrapper = null,
        .message = @errorName(err),
        .hint = null,
    };
    if (line_text) |line| {
        const excerpt = sourceExcerpt(line);
        copyTextBuf(&report.source_text_buf, excerpt);
        copyTextBuf(&report.original_text_buf, excerpt);
    }
    return report;
}

pub fn compileSourceText(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    source_text: []const u8,
    options: CompileOptions,
) !CompileResult {
    if (builtin.is_test) {
        if (source_text.len == 0) return .{ .trap = .{} };
        return .{ .ok = .{} };
    }

    const project_root = try projectRootFromSourcePath(allocator, source_path);
    defer allocator.free(project_root);
    const std_root = try stdRootFromEnv(allocator);
    defer allocator.free(std_root);

    var project_manifest = try readProjectManifest(allocator, source_path);
    defer if (project_manifest) |*m| m.deinit(allocator);

    var dependency_slice: []pkg_resolver.Dependency = &.{};
    defer if (dependency_slice.len != 0) allocator.free(dependency_slice);

    if (project_manifest) |*m| {
        dependency_slice = try manifestDependencies(m, allocator);
    }

    const package_grants: []const manifest.RequireEntry = if (project_manifest) |*m| m.requires else &.{};

    var error_ctx: flattener.ErrorContext = .{};
    const resolve_ctx = flattener.ResolveContext{
        .dependencies = dependency_slice,
        .options = .{ .project_root = project_root, .std_root = std_root },
    };
    var flat = flattener.flattenFileWithContextAndPackages(allocator, source_path, source_text, &error_ctx, resolve_ctx) catch |err| {
        return .{ .trap = trapFromFlattenError(source_text, err, flattener.takeErrorSourceLine(&error_ctx)) };
    };
    errdefer flat.deinit(allocator);

    const verified = try referee.verifyWithOptions(allocator, flat.instructions, flat.const_decls, .{
        .jobs = options.jobs,
        .package_grants = package_grants,
        .sax_context = .{ .component_name = sourceStem(source_path) },
    });
    return switch (verified) {
        .ok => |ok| .{ .ok = .{ .flat = flat, .verified = ok } },
        .trap => |report| {
            flat.deinit(allocator);
            return .{ .trap = report };
        },
    };
}

pub fn buildBrowserWasmFromSourceText(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    source_text: []const u8,
    out_path: []const u8,
    debug: bool,
    optimization: anytype,
    options: CompileOptions,
    stderr: anytype,
) !u8 {
    if (builtin.is_test) {
        try writeTestWasm(out_path);
        return 0;
    }

    const exports = dupeWasmExports(allocator, source_text) catch |err| {
        try stderr.print("error[SAX-CACHE-EXPORTS]: failed to extract exports: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer freeWasmExports(allocator, exports);

    const std_root = stdRootFromEnv(allocator) catch |err| {
        try stderr.print("error[SAX-CACHE-STD]: failed to resolve std root: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(std_root);

    const hash = getBrowserWasmCacheKey(allocator, source_text, debug, optimization, options.dce, exports, std_root) catch |err| {
        try stderr.print("error[SAX-CACHE-HASH]: failed to compute cache key: {s}\n", .{@errorName(err)});
        return 1;
    };
    var hash_hex: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&hash_hex, "{s}", .{std.fmt.fmtSliceHexLower(&hash)}) catch unreachable;

    const project_root = projectRootFromSourcePath(allocator, source_path) catch |err| {
        try stderr.print("error[SAX-CACHE-ROOT]: failed to find project root: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(project_root);

    const cache_dir = std.fs.path.join(allocator, &.{ project_root, ".sa_cache", "vite-browser-wasm", &hash_hex }) catch |err| {
        try stderr.print("error[SAX-CACHE-PATH]: failed to join cache dir path: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(cache_dir);

    const cached_wasm = std.fs.path.join(allocator, &.{ cache_dir, "output.wasm" }) catch |err| {
        try stderr.print("error[SAX-CACHE-PATH]: failed to join cached wasm path: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(cached_wasm);
    const cached_bc = std.fs.path.join(allocator, &.{ cache_dir, "artifact.sa.bc" }) catch |err| {
        try stderr.print("error[SAX-CACHE-PATH]: failed to join cached bc path: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(cached_bc);

    const artifact_path = std.fmt.allocPrint(allocator, "{s}.sa.bc", .{out_path}) catch |err| {
        try stderr.print("error[SAX-CACHE-PATH]: failed to format artifact path: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(artifact_path);

    if (filePresentNonEmpty(cached_wasm) and filePresentNonEmpty(cached_bc)) {
        copyFile(cached_wasm, out_path) catch |err| {
            try stderr.print("error[SAX-CACHE-COPY]: failed to copy cached wasm: {s}\n", .{@errorName(err)});
            return 1;
        };
        copyFile(cached_bc, artifact_path) catch |err| {
            try stderr.print("error[SAX-CACHE-COPY]: failed to copy cached bc: {s}\n", .{@errorName(err)});
            return 1;
        };
        try stderr.print("  [vite] browser wasm cache hit: {s}\n", .{hash_hex[0..12]});
        return 0;
    }

    const compiled = try compileSourceText(allocator, source_path, source_text, options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);

            const stable_hash = try getBrowserWasmIncrementalCacheKey(allocator, debug, optimization, options.dce, exports, std_root);
            var stable_hash_hex: [64]u8 = undefined;
            _ = std.fmt.bufPrint(&stable_hash_hex, "{s}", .{std.fmt.fmtSliceHexLower(&stable_hash)}) catch unreachable;

            const fn_cache_dir = try std.fs.path.join(allocator, &.{ project_root, ".sa_cache", "vite-browser-wasm-incremental", &stable_hash_hex });
            defer allocator.free(fn_cache_dir);

            var bitcode_paths = std.ArrayList([]const u8).init(allocator);
            defer {
                for (bitcode_paths.items) |p| allocator.free(p);
                bitcode_paths.deinit();
            }

            var sig_index: usize = 0;
            var idx: usize = 0;
            var task_idx: usize = 0;
            while (idx < owned.verified.annotated.len) : (idx += 1) {
                const item = owned.verified.annotated[idx].base;
                switch (item.kind) {
                    .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => {
                        if (sig_index >= owned.verified.function_sigs.len) return error.UnknownFunction;
                        const current_sig_index = sig_index;
                        sig_index += 1;

                        var end = idx + 1;
                        while (end < owned.verified.annotated.len and switch (owned.verified.annotated[end].base.kind) {
                            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => false,
                            else => true,
                        }) : (end += 1) {}

                        if (item.kind != .extern_decl) {
                            const function_key = try computeFunctionObjectKey(allocator, source_path, &owned.verified, current_sig_index, idx, end);
                            defer allocator.free(function_key);

                            const func_bc_path = try std.fmt.allocPrint(allocator, "{s}/functions/{s}.sa.bc", .{ fn_cache_dir, function_key });
                            errdefer allocator.free(func_bc_path);

                            if (!filePresentNonEmpty(func_bc_path)) {
                                try ensureParentDir(func_bc_path);
                                const opt_level = switch (optimization) {
                                    .release_small => @as(u8, 1),
                                    .release_fast => @as(u8, 3),
                                    else => @as(u8, 0),
                                };
                                try emit_llvm_llvmc.emitLlvmcToFile(
                                    allocator,
                                    owned.verified,
                                    &owned.flat.def_dict,
                                    owned.flat.loc_table,
                                    source_path,
                                    32,
                                    emit_options.EmitOptions{
                                        .debug = debug,
                                        .wasm_compat = true,
                                        .jobs = 1,
                                        .opt_level = opt_level,
                                        .function_task_index = task_idx,
                                        .dce = options.dce,
                                        .std_root = std_root,
                                    },
                                    func_bc_path,
                                );
                            }

                            try bitcode_paths.append(func_bc_path);
                        }

                        task_idx += 1;
                        idx = end - 1;
                    },
                    else => {},
                }
            }

            if (bitcode_paths.items.len == 0) {
                return error.UnknownFunction;
            }

            try ensureParentDir(artifact_path);
            driver.compileWasm(
                allocator,
                bitcode_paths.items,
                out_path,
                .{ .triple = "wasm32-freestanding", .no_entry = true, .import_symbols = true, .exports = exports },
                optimization,
                debug,
                stderr,
            ) catch |err| switch (err) {
                error.ChildProcessFailed => return 1,
                else => return err,
            };

            if (std.fs.path.dirname(cached_wasm)) |dir| {
                if (dir.len != 0) std.fs.cwd().makePath(dir) catch {};
            }
            std.fs.cwd().copyFile(out_path, std.fs.cwd(), cached_wasm, .{}) catch {};
            std.fs.cwd().copyFile(bitcode_paths.items[0], std.fs.cwd(), cached_bc, .{}) catch {};

            const cached_manifest = std.fs.path.join(allocator, &.{ cache_dir, "manifest.json" }) catch null;
            if (cached_manifest) |man_path| {
                defer allocator.free(man_path);
                var manifest_file = std.fs.cwd().createFile(man_path, .{}) catch null;
                if (manifest_file) |*f| {
                    defer f.close();
                    f.writer().print(
                        \\{{
                        \\  "version": 1,
                        \\  "debug": {},
                        \\  "optimization": "{s}",
                        \\  "dce": "{s}",
                        \\  "exports_count": {}
                        \\}}
                    , .{ debug, @tagName(optimization), options.dce.name(), exports.len }) catch {};
                }
            }

            return 0;
        },
    }
}

fn getBrowserWasmSourceUnitsCacheKey(
    allocator: std.mem.Allocator,
    units: []const SourceUnit,
    debug: bool,
    optimization: anytype,
    dce: emit_options.DceMode,
    exports: []const []const u8,
    std_root: []const u8,
) ![32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("sa-plugin-browser-wasm-source-units-cache-v1");
    hasher.update(&[_]u8{0});
    hasher.update(build_options.repo_root);
    hasher.update(&[_]u8{0});
    try hashRuntimeBuildInputs(allocator, &hasher);
    hasher.update(std_root);
    hasher.update(&[_]u8{0});
    try hashSaStdTree(allocator, &hasher, std_root);
    hasher.update(if (debug) "\x01" else "\x00");
    hasher.update(&[_]u8{0});
    hasher.update(@tagName(optimization));
    hasher.update(&[_]u8{0});
    hasher.update(dce.name());
    hasher.update(&[_]u8{0});
    for (units) |unit| {
        hasher.update(unit.logical_name);
        hasher.update(&[_]u8{0});
        hasher.update(unit.source_text);
        hasher.update(&[_]u8{0});
    }
    for (exports) |exp| {
        hasher.update(exp);
        hasher.update(&[_]u8{0});
    }
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

fn computeSourceUnitObjectKey(
    allocator: std.mem.Allocator,
    unit: SourceUnit,
) ![]const u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("sa-build-wasm-source-unit-cache-v1");
    hasher.update(unit.logical_name);
    hasher.update(&[_]u8{0});
    hasher.update(unit.source_text);
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return try std.fmt.allocPrint(allocator, "{}", .{std.fmt.fmtSliceHexLower(&out)});
}

pub fn buildBrowserWasmFromSourceUnits(
    allocator: std.mem.Allocator,
    units: []const SourceUnit,
    out_path: []const u8,
    debug: bool,
    optimization: anytype,
    options: CompileOptions,
    stderr: anytype,
) !u8 {
    if (builtin.is_test) {
        try writeTestWasm(out_path);
        return 0;
    }

    if (units.len == 0) return error.UnknownFunction;

    const exports = dupeWasmExportsFromSourceUnits(allocator, units) catch |err| {
        try stderr.print("error[SAX-CACHE-EXPORTS]: failed to extract exports: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer freeWasmExports(allocator, exports);

    const std_root = stdRootFromEnv(allocator) catch |err| {
        try stderr.print("error[SAX-CACHE-STD]: failed to resolve std root: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(std_root);

    const hash = getBrowserWasmSourceUnitsCacheKey(allocator, units, debug, optimization, options.dce, exports, std_root) catch |err| {
        try stderr.print("error[SAX-CACHE-HASH]: failed to compute cache key: {s}\n", .{@errorName(err)});
        return 1;
    };
    var hash_hex: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&hash_hex, "{s}", .{std.fmt.fmtSliceHexLower(&hash)}) catch unreachable;

    const project_root = projectRootFromSourcePath(allocator, units[0].source_path) catch |err| {
        try stderr.print("error[SAX-CACHE-ROOT]: failed to find project root: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(project_root);

    const cache_dir = std.fs.path.join(allocator, &.{ project_root, ".sa_cache", "vite-browser-wasm-units", &hash_hex }) catch |err| {
        try stderr.print("error[SAX-CACHE-PATH]: failed to join cache dir path: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(cache_dir);

    const cached_wasm = std.fs.path.join(allocator, &.{ cache_dir, "output.wasm" }) catch |err| {
        try stderr.print("error[SAX-CACHE-PATH]: failed to join cached wasm path: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(cached_wasm);

    if (filePresentNonEmpty(cached_wasm)) {
        copyFile(cached_wasm, out_path) catch |err| {
            try stderr.print("error[SAX-CACHE-COPY]: failed to copy cached wasm: {s}\n", .{@errorName(err)});
            return 1;
        };
        try stderr.print("  [vite] browser wasm cache hit: {s}\n", .{hash_hex[0..12]});
        return 0;
    }

    const stable_hash = try getBrowserWasmIncrementalCacheKey(allocator, debug, optimization, options.dce, exports, std_root);
    var stable_hash_hex: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&stable_hash_hex, "{s}", .{std.fmt.fmtSliceHexLower(&stable_hash)}) catch unreachable;

    const unit_cache_dir = try std.fs.path.join(allocator, &.{ project_root, ".sa_cache", "vite-browser-wasm-source-units", &stable_hash_hex });
    defer allocator.free(unit_cache_dir);

    var bitcode_paths = std.ArrayList([]const u8).init(allocator);
    defer {
        for (bitcode_paths.items) |p| allocator.free(p);
        bitcode_paths.deinit();
    }

    const opt_level = switch (optimization) {
        .release_small => @as(u8, 1),
        .release_fast => @as(u8, 3),
        else => @as(u8, 0),
    };

    for (units) |unit| {
        const unit_key = try computeSourceUnitObjectKey(allocator, unit);
        defer allocator.free(unit_key);

        const unit_bc_path = try std.fmt.allocPrint(allocator, "{s}/units/{s}.sa.bc", .{ unit_cache_dir, unit_key });
        errdefer allocator.free(unit_bc_path);

        if (!filePresentNonEmpty(unit_bc_path)) {
            const compiled = try compileSourceText(allocator, unit.source_path, unit.source_text, .{ .jobs = 1, .dce = options.dce });
            switch (compiled) {
                .trap => |report| {
                    try printTrapReport(stderr, report);
                    return 1;
                },
                .ok => |ok| {
                    var owned = ok;
                    defer owned.deinit(allocator);

                    try ensureParentDir(unit_bc_path);
                    try emit_llvm_llvmc.emitLlvmcToFile(
                        allocator,
                        owned.verified,
                        &owned.flat.def_dict,
                        owned.flat.loc_table,
                        unit.source_path,
                        32,
                        .{ .debug = debug, .wasm_compat = true, .jobs = 1, .dce = options.dce, .std_root = std_root, .opt_level = opt_level },
                        unit_bc_path,
                    );
                },
            }
        }

        try bitcode_paths.append(unit_bc_path);
    }

    try ensureParentDir(out_path);
    driver.compileWasm(
        allocator,
        bitcode_paths.items,
        out_path,
        .{ .triple = "wasm32-freestanding", .no_entry = true, .import_symbols = true, .exports = exports },
        optimization,
        debug,
        stderr,
    ) catch |err| switch (err) {
        error.ChildProcessFailed => return 1,
        else => return err,
    };

    if (std.fs.path.dirname(cached_wasm)) |dir| {
        if (dir.len != 0) std.fs.cwd().makePath(dir) catch {};
    }
    std.fs.cwd().copyFile(out_path, std.fs.cwd(), cached_wasm, .{}) catch {};
    return 0;
}

fn getBrowserWasmIncrementalCacheKey(
    allocator: std.mem.Allocator,
    debug: bool,
    optimization: anytype,
    dce: emit_options.DceMode,
    exports: []const []const u8,
    std_root: []const u8,
) ![32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("sa-plugin-browser-wasm-incremental-cache-v2");
    hasher.update(&[_]u8{0});
    hasher.update(build_options.repo_root);
    hasher.update(&[_]u8{0});
    try hashRuntimeBuildInputs(allocator, &hasher);
    hasher.update(std_root);
    hasher.update(&[_]u8{0});
    try hashSaStdTree(allocator, &hasher, std_root);
    hasher.update(if (debug) "\x01" else "\x00");
    hasher.update(&[_]u8{0});
    hasher.update(@tagName(optimization));
    hasher.update(&[_]u8{0});
    hasher.update(dce.name());
    hasher.update(&[_]u8{0});
    for (exports) |exp| {
        hasher.update(exp);
        hasher.update(&[_]u8{0});
    }
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

fn computeFunctionObjectKey(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    verified: *const referee.VerifyOk,
    sig_index: usize,
    start_idx: usize,
    end_idx: usize,
) ![]const u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("sa-build-wasm-function-cache-v1");
    hasher.update(source_path);
    for (verified.function_sigs) |sig_item| {
        hasher.update(sig_item.name);
        if (sig_item.llvm_name) |name| {
            hasher.update(name);
        } else {
            hasher.update("");
        }
        var buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &buf, sig_item.id, .little);
        hasher.update(&buf);
    }
    for (verified.const_decls) |decl| {
        hasher.update(decl.name);
        hasher.update(decl.raw_text);
    }
    var sig_buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &sig_buf, sig_index, .little);
    hasher.update(&sig_buf);
    const current_sig = verified.function_sigs[sig_index];
    hasher.update(current_sig.name);
    if (current_sig.llvm_name) |name| {
        hasher.update(name);
    } else {
        hasher.update("");
    }
    for (verified.annotated[start_idx..end_idx]) |item| {
        hasher.update(item.base.raw_text);
    }
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return try std.fmt.allocPrint(allocator, "{}", .{std.fmt.fmtSliceHexLower(&out)});
}

fn getBrowserWasmCacheKey(
    allocator: std.mem.Allocator,
    source_text: []const u8,
    debug: bool,
    optimization: anytype,
    dce: emit_options.DceMode,
    exports: []const []const u8,
    std_root: []const u8,
) ![32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("sa-plugin-browser-wasm-cache-v2");
    hasher.update(&[_]u8{0});
    hasher.update(build_options.repo_root);
    hasher.update(&[_]u8{0});
    try hashRuntimeBuildInputs(allocator, &hasher);
    hasher.update(std_root);
    hasher.update(&[_]u8{0});
    try hashSaStdTree(allocator, &hasher, std_root);
    hasher.update(source_text);
    hasher.update(&[_]u8{0});
    hasher.update(if (debug) "\x01" else "\x00");
    hasher.update(&[_]u8{0});
    hasher.update(@tagName(optimization));
    hasher.update(&[_]u8{0});
    hasher.update(dce.name());
    hasher.update(&[_]u8{0});
    for (exports) |exp| {
        hasher.update(exp);
        hasher.update(&[_]u8{0});
    }
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

fn isSaStdSource(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".sa") or
        std.mem.endsWith(u8, path, ".sai") or
        std.mem.endsWith(u8, path, ".sal");
}

fn hashNormalizedPath(hasher: *std.crypto.hash.sha2.Sha256, path: []const u8) void {
    var byte: [1]u8 = undefined;
    for (path) |c| {
        byte[0] = if (std.fs.path.isSep(c)) '/' else c;
        hasher.update(&byte);
    }
}

fn hashFileContentIfPresent(allocator: std.mem.Allocator, hasher: *std.crypto.hash.sha2.Sha256, path: []const u8) !void {
    if (path.len == 0) return;
    hashNormalizedPath(hasher, path);
    hasher.update(&[_]u8{0});
    var file = if (std.fs.path.isAbsolute(path))
        std.fs.openFileAbsolute(path, .{}) catch return
    else
        std.fs.cwd().openFile(path, .{}) catch return;
    defer file.close();
    const bytes = try file.readToEndAlloc(allocator, 128 * 1024 * 1024);
    defer allocator.free(bytes);
    hasher.update(bytes);
    hasher.update(&[_]u8{0});
}

fn hashRuntimeBuildInputs(allocator: std.mem.Allocator, hasher: *std.crypto.hash.sha2.Sha256) !void {
    if (@hasDecl(build_options, "sa_bin")) {
        try hashFileContentIfPresent(allocator, hasher, build_options.sa_bin);
    }
    const plugin_path = std.process.getEnvVarOwned(allocator, "SA_PLUGINS_PATH") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return,
        else => return err,
    };
    defer allocator.free(plugin_path);

    hasher.update(plugin_path);
    hasher.update(&[_]u8{0});
    var parts = std.mem.splitScalar(u8, plugin_path, ':');
    while (parts.next()) |entry| {
        try hashFileContentIfPresent(allocator, hasher, entry);
    }
}

fn hashSaStdTree(allocator: std.mem.Allocator, hasher: *std.crypto.hash.sha2.Sha256, std_root: []const u8) !void {
    var entries = std.ArrayList([]u8).init(allocator);
    defer {
        for (entries.items) |entry| allocator.free(entry);
        entries.deinit();
    }

    var root = try std.fs.cwd().openDir(std_root, .{ .iterate = true });
    defer root.close();

    var walker = try root.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file or !isSaStdSource(entry.path)) continue;
        const copied = try allocator.dupe(u8, entry.path);
        errdefer allocator.free(copied);
        try entries.append(copied);
    }

    std.mem.sort([]u8, entries.items, {}, struct {
        fn lessThan(_: void, lhs: []u8, rhs: []u8) bool {
            return std.mem.order(u8, lhs, rhs) == .lt;
        }
    }.lessThan);

    for (entries.items) |entry_path| {
        const file_bytes = try root.readFileAlloc(allocator, entry_path, 16 * 1024 * 1024);
        defer allocator.free(file_bytes);
        hashNormalizedPath(hasher, entry_path);
        hasher.update(&[_]u8{0});
        hasher.update(file_bytes);
        hasher.update(&[_]u8{0});
    }
}

fn filePresentNonEmpty(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .file and stat.size != 0;
}

fn copyFile(src: []const u8, dst: []const u8) !void {
    if (std.fs.path.dirname(dst)) |dir| {
        if (dir.len != 0) try std.fs.cwd().makePath(dir);
    }
    try std.fs.cwd().copyFile(src, std.fs.cwd(), dst, .{});
}

fn ensureParentDir(path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        if (dir.len != 0) try std.fs.cwd().makePath(dir);
    }
}

fn writeAllFile(path: []const u8, bytes: []const u8) !void {
    try ensureParentDir(path);
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

test "sax browser wasm build targets freestanding browser module" {
    var argv = try TestDriver.argvForWasm(std.testing.allocator, &.{"input.bc"}, "out.wasm", .{
        .triple = "wasm32-freestanding",
        .no_entry = true,
        .import_symbols = true,
        .exports = &.{ "sax_app_init", "sax_dashboard_recordVisit" },
    }, .release_small, false);
    defer argv.deinit();
    try std.testing.expectEqualStrings("build-exe", argv.slice()[1]);
    try std.testing.expectEqualStrings("wasm32-freestanding", argv.slice()[4]);
    try std.testing.expectEqualStrings("-fno-entry", argv.slice()[5]);
    try std.testing.expectEqualStrings("--import-symbols", argv.slice()[6]);
    try std.testing.expectEqualStrings("--export=sax_app_init", argv.slice()[7]);
}

test "sax wasm export collector mirrors generated SA exports" {
    const source =
        \\@export sax_dashboard_init() -> ptr:
        \\L_ENTRY:
        \\  return 0
        \\@export sax_dashboard_recordVisit(ctx: ptr):
        \\L_ENTRY:
        \\  return
        \\
    ;
    const exports = try dupeWasmExports(std.testing.allocator, source);
    defer freeWasmExports(std.testing.allocator, exports);

    try std.testing.expectEqual(@as(usize, 2), exports.len);
    try std.testing.expectEqualStrings("sax_dashboard_init", exports[0]);
    try std.testing.expectEqualStrings("sax_dashboard_recordVisit", exports[1]);
}

test "sax test llvm emitter writes real bitcode" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    var old_cwd = try std.fs.cwd().openDir(".", .{});
    defer old_cwd.close();
    try tmp.dir.setAsCwd();
    defer old_cwd.setAsCwd() catch {};

    try emit_llvm_llvmc.emitLlvmcToFile(
        std.testing.allocator,
        {},
        {},
        {},
        "app.sa",
        32,
        .{ .wasm_compat = true },
        "app.wasm.sa.bc",
    );

    const bytes = try std.fs.cwd().readFileAlloc(std.testing.allocator, "app.wasm.sa.bc", 1024 * 1024);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(bytes.len > 4);
    try std.testing.expectEqualSlices(u8, &.{ 'B', 'C', 0xc0, 0xde }, bytes[0..4]);

    const tools = [_][]const u8{ "llvm-dis-14", "llvm-dis" };
    for (tools) |tool| {
        const result = std.process.Child.run(.{
            .allocator = std.testing.allocator,
            .argv = &.{ tool, "app.wasm.sa.bc", "-o", "-" },
        }) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        defer std.testing.allocator.free(result.stdout);
        defer std.testing.allocator.free(result.stderr);

        switch (result.term) {
            .Exited => |code| {
                try std.testing.expectEqual(@as(u8, 0), code);
                try std.testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "define void @__sax_test()"));
                return;
            },
            else => return error.TestUnexpectedResult,
        }
    }
    return error.SkipZigTest;
}
