const std = @import("std");

/// NOTE(Zig 0.17): `Build.pathFromRoot` / `getInstallPath` were removed.
fn pathFromRoot(b: *std.Build, sub_path: []const u8) []u8 {
    const root_path = b.root.root_dir.path orelse ".";
    return std.fs.path.resolve(b.allocator, &.{ root_path, sub_path }) catch @panic("OOM");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const sa_repo_root = b.option([]const u8, "sa-repo-root", "SA repository root used to resolve sa_std imports.") orelse "../sci";
    const sa_bin = b.option([]const u8, "sa-bin", "Path to the SA host binary used for React integration tests.") orelse b.pathJoin(&.{ sa_repo_root, "zig-out/bin/sa" });
    const llvm_include_dir = b.option([]const u8, "llvm-include-dir", "LLVM C API include directory.") orelse "/usr/lib/llvm-20/include";
    const llvm_lib_dir = b.option([]const u8, "llvm-lib-dir", "LLVM library directory.") orelse "/usr/lib/llvm-20/lib";
    const llvm_lib_name = b.option([]const u8, "llvm-lib-name", "LLVM system library name.") orelse "LLVM-20";
    // NOTE(Zig 0.17): sci-style `-Dllvm` bootstrap switch. When false, link the
    // stub (same C ABI, returns "backend disabled" at runtime) instead of LLVM.
    const enable_llvm = b.option(bool, "llvm", "Link the LLVM-C backend (needs LLVM dev headers/lib). Use -Dllvm=false for bootstrap.") orelse true;
    validateLlvmConfig(b, enable_llvm, llvm_include_dir, llvm_lib_dir, llvm_lib_name);

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "repo_root", sa_repo_root);
    build_options.addOption([]const u8, "sa_bin", sa_bin);

    const plugin_api = b.createModule(.{
        .root_source_file = b.path("src/plugin_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/plugin.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const sla_handler_bridge = b.createModule(.{
        .root_source_file = b.path("../sa_plugin_sla/src/handler_bridge.zig"),
        .target = target,
        .optimize = optimize,
    });
    const sio_module = b.createModule(.{
        // NOTE: sibling checkout layout (../sci), cwd_relative supports outside-root paths.
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ "../sci", "src", "sa_io.zig" }) },
        .target = target,
        .optimize = optimize,
    });
    root_module.addImport("plugin_api", plugin_api);
    root_module.addImport("sla_handler_bridge", sla_handler_bridge);
    root_module.addImport("sio", sio_module);
    sla_handler_bridge.addImport("sio", sio_module);
    root_module.addOptions("build_options", build_options);
    addLlvmcSupportToModule(b, root_module, enable_llvm, llvm_include_dir, llvm_lib_dir, llvm_lib_name);

    const lib = b.addLibrary(.{
        .name = "react",
        .root_module = root_module,
        .linkage = .dynamic,
    });
    b.installArtifact(lib);

    const tests = b.addTest(.{ .root_module = root_module });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run plugin tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(b.getInstallStep());

    addSaContractTest(b, test_step, sa_bin, "tests/react_init_contract.sa");
    addSaContractTest(b, test_step, sa_bin, "tests/react_ptr_state_contract.sa");
    addSaContractTest(b, test_step, sa_bin, "tests/react_expr_interpolation_contract.sa");
    addSaContractTest(b, test_step, sa_bin, "tests/react_event_binding_contract.sa");
    addSaContractTest(b, test_step, sa_bin, "tests/react_typed_state_contract.sa");

    const installed_lib = pathFromRoot(b, "zig-out/lib/libreact.so");
    const plugin_lib_input = lib.getEmittedBin();

    const wasm_verify_module = b.createModule(.{
        .root_source_file = b.path("tools/verify_react_demo_wasm.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    const wasm_verify = b.addExecutable(.{
        .name = "verify-react-demo-wasm",
        .root_module = wasm_verify_module,
    });

    addDemoSuite(b, test_step, sa_bin, installed_lib, plugin_lib_input, wasm_verify, .{
        .source = "demos/react_counter.sax",
        .out_name = "react-counter",
        .runtime_case = "counter",
        .exports = &.{
            "sax_counter_init",
            "sax_counter_render",
            "sax_counter_destroy",
            "sax_counter_inc",
            "sax_counter_dec",
            "sax_counter_reset",
        },
    });

    addDemoSuite(b, test_step, sa_bin, installed_lib, plugin_lib_input, wasm_verify, .{
        .source = "demos/react_counter_sla.sax",
        .out_name = "react-counter-sla",
        .runtime_case = "counter",
        .exports = &.{
            "sax_counter_init",
            "sax_counter_render",
            "sax_counter_destroy",
            "sax_counter_inc",
            "sax_counter_dec",
            "sax_counter_reset",
        },
    });

    addDemoSuite(b, test_step, sa_bin, installed_lib, plugin_lib_input, wasm_verify, .{
        .source = "demos/react_todolist.sax",
        .out_name = "react-todolist",
        .runtime_case = "todo",
        .exports = &.{
            "sax_todolist_init",
            "sax_todolist_render",
            "sax_todolist_destroy",
            "sax_todolist_add",
            "sax_todolist_removeLast",
        },
    });

    addDemoSuite(b, test_step, sa_bin, installed_lib, plugin_lib_input, wasm_verify, .{
        .source = "demos/react_slider.sax",
        .out_name = "react-slider",
        .runtime_case = "typed",
        .exports = &.{
            "sax_typedlab_init",
            "sax_typedlab_render",
            "sax_typedlab_destroy",
            "sax_typedlab_bump",
        },
    });

    addDemoSuite(b, test_step, sa_bin, installed_lib, plugin_lib_input, wasm_verify, .{
        .source = "demos/react_composition.sax",
        .out_name = "react-composition",
        .runtime_case = "composition",
        .exports = &.{
            "sax_app_render",
            "sax_app_destroy",
            "sax_app_inc",
            "sax_layout_init",
            "sax_layout_mount",
            "sax_layout_slot",
            "sax_layout_set_title_str",
            "sax_layout_render",
            "sax_layout_destroy",
            "sax_counterbadge_mount",
            "sax_counterbadge_slot",
            "sax_counterbadge_set_count",
            "sax_counterbadge_render",
            "sax_counterbadge_destroy",
            "sax_objectbadge_mount",
            "sax_objectbadge_slot",
            "sax_objectbadge_set_config_str",
            "sax_objectbadge_render",
            "sax_objectbadge_destroy",
        },
    });

    addDemoSuite(b, test_step, sa_bin, installed_lib, plugin_lib_input, wasm_verify, .{
        .source = "demos/react_component_events.sax",
        .out_name = "react-component-events",
        .runtime_case = "component-events",
        .exports = &.{
            "sax_eventforwarding_init",
            "sax_eventforwarding_render",
            "sax_eventforwarding_destroy",
            "sax_eventforwarding_record_click",
            "sax_eventforwarding_record_change",
            "sax_actionbutton_mount",
            "sax_actionbutton_root",
            "sax_actionbutton_destroy",
            "sax_inputshell_mount",
            "sax_inputshell_root",
            "sax_inputshell_destroy",
        },
    });

    addDemoSuite(b, test_step, sa_bin, installed_lib, plugin_lib_input, wasm_verify, .{
        .source = "demos/react_dom_surface.sax",
        .out_name = "react-dom-surface",
        .runtime_case = "dom-surface",
        .exports = &.{
            "sax_domsurface_init",
            "sax_domsurface_render",
            "sax_domsurface_destroy",
            "sax_domsurface_bump",
        },
    });

    addDemoSuite(b, test_step, sa_bin, installed_lib, plugin_lib_input, wasm_verify, .{
        .source = "demos/react_controlled_input.sax",
        .out_name = "react-controlled-input",
        .runtime_case = "controlled-input",
        .exports = &.{
            "sax_controlledinput_init",
            "sax_controlledinput_render",
            "sax_controlledinput_destroy",
            "sax_controlledinput_sync",
            "sax_controlledinput_toggle",
            "sax_controlledinput_submit",
        },
    });
}

const DemoSuite = struct {
    source: []const u8,
    out_name: []const u8,
    runtime_case: []const u8,
    exports: []const []const u8,
};

fn addSaContractTest(b: *std.Build, test_step: *std.Build.Step, sa_bin: []const u8, test_path: []const u8) void {
    const cmd = b.addSystemCommand(&.{ sa_bin, "test", test_path });
    cmd.addFileInput(b.path(test_path));
    test_step.dependOn(&cmd.step);
}

fn addDemoSuite(
    b: *std.Build,
    test_step: *std.Build.Step,
    sa_bin: []const u8,
    installed_lib: []const u8,
    plugin_lib_input: std.Build.LazyPath,
    wasm_verify: *std.Build.Step.Compile,
    demo: DemoSuite,
) void {
    const demo_input = b.path(demo.source);

    const check = b.addSystemCommand(&.{ sa_bin, "react", "check", demo.source });
    check.setEnvironmentVariable("SA_PLUGINS_PATH", installed_lib);
    check.addFileInput(plugin_lib_input);
    check.addFileInput(demo_input);
    check.step.dependOn(b.getInstallStep());
    test_step.dependOn(&check.step);

    const build_cmd = b.addSystemCommand(&.{ sa_bin, "react", "build", demo.source, "--out-dir" });
    const output = build_cmd.addOutputDirectoryArg(demo.out_name);
    build_cmd.setEnvironmentVariable("SA_PLUGINS_PATH", installed_lib);
    build_cmd.addFileInput(plugin_lib_input);
    build_cmd.addFileInput(demo_input);
    build_cmd.step.dependOn(b.getInstallStep());
    test_step.dependOn(&build_cmd.step);

    const run_wasm_verify = b.addRunArtifact(wasm_verify);
    run_wasm_verify.addDirectoryArg(output);
    run_wasm_verify.addArgs(demo.exports);
    test_step.dependOn(&run_wasm_verify.step);

    const run_runtime_verify = b.addSystemCommand(&.{ "node", "tools/verify_react_runtime.mjs" });
    run_runtime_verify.addFileInput(b.path("tools/verify_react_runtime.mjs"));
    run_runtime_verify.addDirectoryArg(output);
    run_runtime_verify.addArg(demo.runtime_case);
    test_step.dependOn(&run_runtime_verify.step);
}

fn addLlvmcSupportToModule(
    b: *std.Build,
    module: *std.Build.Module,
    enable_llvm: bool,
    include_dir: []const u8,
    lib_dir: []const u8,
    lib_name: []const u8,
) void {
    if (enable_llvm) {
        module.addCSourceFile(.{ .file = b.path("src/emit_llvm_llvmc_shim.c"), .flags = &.{} });
        linkLLVMToModule(module, include_dir, lib_dir, lib_name);
    } else {
        module.addCSourceFile(.{ .file = b.path("src/emit_llvm_llvmc_stub.c"), .flags = &.{"-fno-sanitize=all"} });
    }
}

fn pathExists(io: std.Io, path: []const u8) bool {
    if (std.fs.path.isAbsolute(path)) {
        std.Io.Dir.accessAbsolute(io, path, .{}) catch return false;
    } else {
        std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    }
    return true;
}

fn validateLlvmConfig(b: *std.Build, enable_llvm: bool, include_dir: []const u8, lib_dir: []const u8, lib_name: []const u8) void {
    if (!enable_llvm) return;
    const io = b.graph.io;
    const core_header = std.fs.path.join(b.allocator, &.{ include_dir, "llvm-c", "Core.h" }) catch
        failLlvmConfig("failed to construct LLVM include path", .{});
    defer b.allocator.free(core_header);
    if (!pathExists(io, core_header)) {
        failLlvmConfig("LLVM-C header not found: {s}\n  pass -Dllvm-include-dir=<path> or use -Dllvm=false for bootstrap", .{core_header});
    }
    if (!pathExists(io, lib_dir)) {
        failLlvmConfig("LLVM library directory not found: {s}\n  pass -Dllvm-lib-dir=<path> or use -Dllvm=false for bootstrap", .{lib_dir});
    }
    const candidates = [_][]const u8{
        lib_name,
        b.fmt("lib{s}.so", .{lib_name}),
        b.fmt("lib{s}.a", .{lib_name}),
    };
    for (candidates) |candidate| {
        const p = std.fs.path.join(b.allocator, &.{ lib_dir, candidate }) catch continue;
        defer b.allocator.free(p);
        if (pathExists(io, p)) return;
    }
    failLlvmConfig("LLVM library not found in {s} for -Dllvm-lib-name={s}\n  pass explicit LLVM paths or use -Dllvm=false for bootstrap", .{ lib_dir, lib_name });
}

fn failLlvmConfig(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("error: LLVM-C backend configuration failed\n  " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

fn addLlvmcShimToModule(b: *std.Build, module: *std.Build.Module) void {
    module.addCSourceFile(.{ .file = b.path("src/emit_llvm_llvmc_shim.c"), .flags = &.{} });
}

fn linkLLVMToModule(module: *std.Build.Module, include_dir: []const u8, lib_dir: []const u8, lib_name: []const u8) void {
    module.addSystemIncludePath(.{ .cwd_relative = include_dir });
    module.addLibraryPath(.{ .cwd_relative = lib_dir });
    module.linkSystemLibrary(lib_name, .{});
}
