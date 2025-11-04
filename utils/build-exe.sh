#!/usr/bin/env bash
# zig build-exe 
# 
# 1. Setup project directory,
# 2. download dependencies, and 
# 3. compile artifacts
# 4. run zig build-exe

# NOTE: RUN FROM PROJECT ROOT DIRECTORY

# Download dependencies
if [[ ! -e './c-includes' ]]; then
  echo '(I): creating "c-includes" directory.'
  mkdir './c-includes';
fi

if [[ ! -e "./c-includes/sqlite-amalgamation-346100.zip" ]]; then
  echo '(I): downloading dependency source files'
  cd c-includes;
  wget https://www.sqlite.org/2024/sqlite-amalgamation-3460100.zip;
  unzip sqlite-amalgamation-3460100.zip;
  cd ..;
fi

# Compile C-dependencies
if [[ ! -e "./c-includes/sqlite-amalgamation-346100/libsqlite3.a" ]]; then
  echo '(I): compile c-libs'
  cd c-includes;
  cd sqlite-amalgamation-3460100;
  
  gcc -c sqlite3.c -o sqlite3.o
  ar rcs libsqlite3.a sqlite3.o
  
  cd ../..;
fi


# Run zig-build script
echo '(I): zig build-exe'
# zig build-exe -lc -I ./c-includes/sqlite-amalgamation-3460100 -L ./c-includes/sqlite-amalgamation-3460100 -lsqlite3  --dep default_config -Mnote=./src/note.zig -Mdefault_config=./exe-defaults/default_config_dev.zig 

# For installing in user home dir
zig build-exe -lc -I ./c-includes/sqlite-amalgamation-3460100 -L ./c-includes/sqlite-amalgamation-3460100 -lsqlite3  --dep default_config -Mnote=./src/note.zig -Mdefault_config=./exe-defaults/default_config_user.zig

