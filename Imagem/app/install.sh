#!/bin/sh
set -e

# Ajusta links simbólicos para libs esperadas pelo binário
#ln -s /usr/lib/x86_64-linux-gnu/libtommath.so.1 /usr/lib/x86_64-linux-gnu/libtommath.so.0
#ln -s /usr/lib/x86_64-linux-gnu/libncurses.so.6 /usr/lib/x86_64-linux-gnu/libncurses.so.5

# Prepara estrutura de diretórios
mkdir -p /opt/rinha /opt/rinha/Logs

# Move binário e bibliotecas
cp /docker_build/app/Rinha /opt/rinha/Rinha
cp /docker_build/app/app.init /opt/rinha/app.init

# Garante permissão de execução
chmod +x /opt/rinha/Rinha
chmod +x /opt/rinha/app.init

# Remove arquivos temporários
rm -f /docker_build/app/Rinha
rm -f /docker_build/app/app.init

exit 0

