#!/bin/sh
set -e

# Limpa cache do APT e listas de pacotes
apt-get clean
rm -rf /var/lib/apt/lists/*

# Remove diretórios temporários
rm -rf /tmp/* /var/tmp/*

# Remove pasta docker_build completa
rm -rf /docker_build

# Remove bytecode Python, se houver
find / -mount -name '*.pyc' -delete || true
find / -mount -name '__pycache__' -delete || true

# Remove chaves SSH padrão (se tiver sido gerado por build base)
rm -f /etc/ssh/ssh_host_* || true
