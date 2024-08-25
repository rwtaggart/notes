# notes
Simple command-line notes app

# Install
1. Create personal `lib` and `bin` directories
    ```sh
    mkdir $HOME/lib
    mkdir $HOME/bin
    ```

1. Clone the repo and link it up
    ```sh
    git clone https://github.com/rwtaggart/notes.git $HOME/lib/notes
    ln -s $HOME/lib/notes/zig-out/bin/note $HOME/bin/note
    ```

1. Build the binary
    ```sh
    cd $HOME/lib/notes
    zig build -DuseHome
    ```

# Dependencies
Zig - [https://ziglang.org/](https://ziglang.org/)


# Build
Note: `zig build` requires additional parameters. Do not use `zig.build` yet.

```sh
zig build-exe -I /opt/homebrew/Cellar/sqlite/3.46.0/include -L /opt/homebrew/Cellar/sqlite/3.46.0/lib -lsqlite3 ./src/note.zig
```

_**Question:** How do I include c-library with cImport and zig build?_  
See [discord post](https://discord.com/channels/605571803288698900/1274576428452548731) for details.
