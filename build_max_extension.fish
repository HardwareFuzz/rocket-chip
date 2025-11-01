#!/usr/bin/env fish

# Rocket Chip Maximum Extension Configuration Build Script
# This script builds Rocket Chip with maximum extensions (B, FP16, Hypervisor)
# and commit log enabled for detailed instruction tracing

set -g SCRIPT_DIR (dirname (status -f))
set -g PROJECT_ROOT $SCRIPT_DIR
set -g BUILD_DIR $PROJECT_ROOT/out
set -g RESULT_DIR $PROJECT_ROOT/build_result

# Color output
set -g RED '\033[0;31m'
set -g GREEN '\033[0;32m'
set -g YELLOW '\033[1;33m'
set -g BLUE '\033[0;34m'
set -g NC '\033[0m' # No Color

function print_info
    printf "%b[INFO]%b %s\n" "$BLUE" "$NC" "$argv"
end

function print_success
    printf "%b[SUCCESS]%b %s\n" "$GREEN" "$NC" "$argv"
end

function print_warning
    printf "%b[WARNING]%b %s\n" "$YELLOW" "$NC" "$argv"
end

function print_error
    printf "%b[ERROR]%b %s\n" "$RED" "$NC" "$argv"
end

function print_banner
    echo ""
    echo "================================================"
    echo "  Rocket Chip Maximum Extension Builder"
    echo "================================================"
    echo ""
end

function show_usage
    echo "Usage: $argv[1] [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --rv64          Build RV64 configuration"
    echo "  --rv32          Build RV32 configuration"
    echo "  --rv32-no-d     Build RV32 configuration without the D extension"
    echo "  --all           Build all configurations"
    echo "  --clean         Clean build directory first"
    echo "  --help, -h      Show this help message"
    echo ""
    echo "Configurations:"
    echo "  RV64: MaxExtensionRV64ConfigWithTrace"
    echo "    - 64-bit RISC-V"
    echo "    - B extension (Zba, Zbb, Zbs)"
    echo "    - Zicond extension (czero.eqz, czero.nez)"
    echo "    - FP16 support"
    echo "    - Hypervisor extension"
    echo "    - Commit log enabled"
    echo ""
    echo "  RV32: MaxExtensionRV32ConfigWithTrace"
    echo "    - 32-bit RISC-V"
    echo "    - B extension (Zba, Zbb, Zbs)"
    echo "    - Zicond extension (czero.eqz, czero.nez)"
    echo "    - FP16 support"
    echo "    - Commit log enabled"
    echo ""
    echo "  RV32 (No D): MaxExtensionRV32NoDConfigWithTrace"
    echo "    - 32-bit RISC-V"
    echo "    - B extension (Zba, Zbb, Zbs)"
    echo "    - Zicond extension (czero.eqz, czero.nez)"
    echo "    - FP16 support"
    echo "    - D extension disabled"
    echo "    - Commit log enabled"
    echo ""
    echo "Examples:"
    echo "  $argv[1] --rv64             # Build RV64 only"
    echo "  $argv[1] --rv32-no-d        # Build RV32 (No D) only"
    echo "  $argv[1] --all              # Build all configurations"
    echo ""
end

# Parse arguments
set -g BUILD_VERILOG 1
set -g BUILD_EMULATOR 1
set -g CLEAN_FIRST 0
set -g TARGETS
set -g ALL_SELECTED 0

if test (count $argv) -eq 0
    # Default: build RV64, verilog + emulator
    set -g TARGETS rv64
else
    for arg in $argv
        switch $arg
            case '--help' '-h'
                show_usage (status -f)
                exit 0
            case '--rv64'
                if not contains -- "rv64" $TARGETS
                    set -ag TARGETS "rv64"
                end
            case '--rv32'
                if not contains -- "rv32" $TARGETS
                    set -ag TARGETS "rv32"
                end
            case '--rv32-no-d'
                if not contains -- "rv32-no-d" $TARGETS
                    set -ag TARGETS "rv32-no-d"
                end
            case '--all'
                set -g TARGETS rv64 rv32 rv32-no-d
                set -g ALL_SELECTED 1
            case '--clean'
                set CLEAN_FIRST 1
            case '*'
                print_error "Unknown option: $arg"
                show_usage (status -f)
                exit 1
        end
    end
    
    if test $ALL_SELECTED -eq 1
        # already set to all targets
    else if test (count $TARGETS) -eq 0
        set -g TARGETS rv64
    end
end

function build_config
    set config $argv[1]
    set arch $argv[2]
    set artifact $argv[3]
    
    print_info "Building configuration: $config ($arch)"
    
    # Generate Verilog
    if test $BUILD_VERILOG -eq 1
        print_info "Generating Verilog for $config..."
        set start_time (date +%s)
        
        if mill emulator[freechips.rocketchip.system.TestHarness,freechips.rocketchip.system.$config].mfccompiler.compile
            set end_time (date +%s)
            set duration (math $end_time - $start_time)
            print_success "Verilog generation completed in $duration seconds"
            
            # Show generated files
            set verilog_dir "$BUILD_DIR/emulator/freechips.rocketchip.system.TestHarness/freechips.rocketchip.system.$config/mfccompiler/compile.dest"
            if test -d $verilog_dir
                print_info "Verilog files generated in: $verilog_dir"
                echo "  Files:"
                ls -lh $verilog_dir | grep -E '\.(v|sv)$' | awk '{print "    " $9 " (" $5 ")"}'
            end
        else
            print_error "Verilog generation failed for $config"
            return 1
        end
    end
    
    # Build Verilator emulator
    if test $BUILD_EMULATOR -eq 1
        print_info "Building Verilator emulator for $config..."
        print_warning "This may take 10-30 minutes depending on your machine..."
        set start_time (date +%s)
        
        if mill emulator[freechips.rocketchip.system.TestHarness,freechips.rocketchip.system.$config].verilator.elf
            set end_time (date +%s)
            set duration (math $end_time - $start_time)
            set minutes (math $duration / 60)
            set seconds (math $duration % 60)
            print_success "Emulator build completed in $minutes minutes $seconds seconds"
            
            # Show emulator location
            set emulator_path "$BUILD_DIR/emulator/freechips.rocketchip.system.TestHarness/freechips.rocketchip.system.$config/verilator/elf.dest/emulator"
            if test -f $emulator_path
                print_success "Emulator binary: $emulator_path"
                set size (du -h $emulator_path | cut -f1)
                print_info "Binary size: $size"
                
                if test -n "$artifact"
                    if not test -d $RESULT_DIR
                        mkdir -p $RESULT_DIR
                    end
                    set dest_path "$RESULT_DIR/$artifact"
                    cp -f $emulator_path $dest_path
                    print_success "Copied emulator to $dest_path"
                end
            end
        else
            print_error "Emulator build failed for $config"
            return 1
        end
    end
    
    return 0
end

# Main execution
print_banner

# Change to project directory
cd $PROJECT_ROOT
print_info "Project root: $PROJECT_ROOT"

# Clean if requested
if test $CLEAN_FIRST -eq 1
    print_warning "Cleaning build directory..."
    if test -d $BUILD_DIR
        rm -rf $BUILD_DIR
        print_success "Build directory cleaned"
    else
        print_info "Build directory does not exist, skipping clean"
    end
end

# Build configurations
set -g FAILED_BUILDS
set -g DID_BUILD_RV64 0
set -g DID_BUILD_RV32 0
set -g DID_BUILD_RV32_NO_D 0

set last_target $TARGETS[-1]

for target in $TARGETS
    switch $target
        case 'rv64'
            set config "MaxExtensionRV64ConfigWithTrace"
            set label "RV64"
            set artifact "rocket_rv64"
        case 'rv32'
            set config "MaxExtensionRV32ConfigWithTrace"
            set label "RV32"
            set artifact "rocket_rv32"
        case 'rv32-no-d'
            set config "MaxExtensionRV32NoDConfigWithTrace"
            set label "RV32 (No D)"
            set artifact "rocket_rv32_no_d"
        case '*'
            print_warning "Unknown build target: $target (skipping)"
            continue
    end

    if not build_config $config "$label" "$artifact"
        set -a FAILED_BUILDS "$label"
    else
        switch $target
            case 'rv64'
                set DID_BUILD_RV64 1
            case 'rv32'
                set DID_BUILD_RV32 1
            case 'rv32-no-d'
                set DID_BUILD_RV32_NO_D 1
        end
    end

    if test "$target" != "$last_target"
        echo ""
    end
end

# Summary
echo ""
echo "================================================"
echo "  Build Summary"
echo "================================================"

if test (count $FAILED_BUILDS) -eq 0
    print_success "All builds completed successfully!"
    echo ""
    print_info "Next steps:"
    echo "  1. Run tests with the emulator:"
    if test $DID_BUILD_RV64 -eq 1
        echo "     \$BUILD_DIR/emulator/.../MaxExtensionRV64ConfigWithTrace/.../emulator <test.riscv>"
    end
    if test $DID_BUILD_RV32 -eq 1
        echo "     \$BUILD_DIR/emulator/.../MaxExtensionRV32ConfigWithTrace/.../emulator <test.riscv>"
    end
    if test $DID_BUILD_RV32_NO_D -eq 1
        echo "     \$BUILD_DIR/emulator/.../MaxExtensionRV32NoDConfigWithTrace/.../emulator <test.riscv>"
    end
    echo ""
    echo "  2. View commit logs:"
    echo "     The emulator will output detailed instruction trace including:"
    echo "     - X register writes: <priv> 0x<pc> (0x<inst>) x<rd> 0x<data>"
    echo "     - F register writes: <priv> 0x<pc> (0x<inst>) f<rd> 0x<data>"
    echo "     - Memory stores: <priv> 0x<pc> (STORE) addr=0x<addr> data=0x<data> size=<size>"
    echo "     - Exceptions: <priv> 0x<pc> (0x<inst>) EXCEPTION cause=0x<cause> tval=0x<tval>"
    echo ""
    echo "  3. For Verilog simulation, use the generated .v/.sv files in:"
    echo "     \$BUILD_DIR/emulator/.../mfccompiler/compile.dest/"
    echo ""
    echo "  4. Emulator binaries copied to:"
    echo "     $RESULT_DIR"
    echo ""
    exit 0
else
    print_error "Some builds failed: $FAILED_BUILDS"
    echo ""
    print_info "Check the error messages above for details"
    exit 1
end
