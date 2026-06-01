# Zig Install

**Required Dependencies**  
This project requires `zig`: follow these instructions to download and install `zig 0.13.0`.


1. Create personal `lib` and `bin` as subdirectories of `.local`
    ```sh
    mkdir -p $HOME/.local/lib;
    mkdir -p $HOME/.local/bin;
    ```


1. Download the [zig 0.13.0](https://ziglang.org/download/#release-0.13.0) runtime for your system.
    ```sh
    cd $HOME/.local/lib;
    wget <url-to-zig-release-0.13.0>
    ```

1. Extract the source files:
    ```sh
    cd $HOME/.local/lib;
    tar -xf  <path/to/zig-release-0.13.0.tar.xz>
    ```

1. Create executable link `.local/bin/zig`
    ```sh
    ln -s  $HOME/.local/lib/<zig-release-0.13.0>/zig  $HOME/.local/bin/zig
    ```
