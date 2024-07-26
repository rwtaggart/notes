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
