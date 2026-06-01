# notes
Simple command-line notes app

# Install
**Required Dependencies**  
This project requires `zig`: follow [these instructions](docs/ZIG-INSTALL.md) to download and install `zig 0.13.0`.

1. Create personal `lib` and `bin` as subdirectories of `.local`
    ```sh
    mkdir -p $HOME/.local/lib;
    mkdir -p $HOME/.local/bin;
    ```

1. Clone the repo and link it up
    ```sh
    git clone https://github.com/rwtaggart/notes.git $HOME/lib/notes;
    ln -s $HOME/lib/notes/zig-out/bin/note $HOME/bin/note;
    ```

1. Build the binary
    ```sh
    cd $HOME/lib/notes;
    ./utils/build-exe.sh
    ```

# Dependencies
Name | URL
--: | ---
Zig | [https://ziglang.org/](https://ziglang.org/)
SQLite | [https://www.sqlite.org/cintro.html](https://www.sqlite.org/cintro.html)


# Developer Notes
Other notes of things required for development.

### zig build
```sh
    zig build -Doptimize=ReleaseSafe -DuseHome;
```

### Build Dependencies
`zig build` manages the external C dependencies for us. `./build.zig.zon` was configured with:
```sh
zig fetch --save=SQLite3 https://www.sqlite.org/2024/sqlite-amalgamation-3460100.zip
```
