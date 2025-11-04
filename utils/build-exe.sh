#!/usr/bin/env bash
# zig build-exe 
# 
# 1. Setup project directory,
# 2. download dependencies, and 
# 3. compile artifacts
# 4. run zig build-exe

# NOTE: RUN FROM PROJECT ROOT DIRECTORY

# Download dependencies
if [ -z "./c-includes/sqlite-amalgamation-346100.zip" ]; then
  echo '(I): creating "c-includes' directory.'
  cd c-includes;
  wget https://www.sqlite.org/2024/sqlite-amalgamation-3460100.zip;
  unzip sqlite-amalgamation-3460100.zip;
  cd ..;
fi

# Compile C-dependencies
cd c-includes;
cd sqlite-amalgamation-340100;

gcc -c sqlite3.c -o sqlite3.o
ar rcs libsqlite3.a sqlite3.o

cd ../..;


# Run zig-build script
zig build-exe -lc -I ./c-includes/sqlite-amalgamation-3460100 -L ./c-includes/sqlite-amalgamation-3460100 -lsqlite3  --dep default_config -Mnote=./src/note.zig -Mdefault_config=./build-exe-defaults/default_config_dev.zig

# For installing in user home dir
# zig build-exe -lc -I ./c-includes/sqlite-amalgamation-3460100 -L ./c-includes/sqlite-amalgamation-3460100 -lsqlite3  --dep default_config -Mnote=./src/note.zig -Mdefault_config=./build-exe-defaults/default_config_user.zig

