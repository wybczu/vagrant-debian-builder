#!/bin/sh

# additional packages
apt-get install -y mc zip unzip git tig subversion \
		   zip unzip bzip2 htop

apt-get -y autoremove
apt-get clean

# sudo configuration
cat <<EOF > /etc/sudoers.d/00-vagrant-user
vagrant ALL=(ALL) NOPASSWD:ALL
EOF

# empty motd
echo -n > /etc/motd

# default editor
update-alternatives --set editor /usr/bin/vim.nox

# sane vimrc...
cat <<EOV > /etc/vim/vimrc.local
syntax on
set background=dark

if has("autocmd")
  au BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif
endif

if has("autocmd")
  filetype plugin indent on
endif

set showcmd		" Show (partial) command in status line.
set showmatch		" Show matching brackets.
set ignorecase		" Do case insensitive matching
set smartcase		" Do smart case matching
set incsearch		" Incremental search
set autowrite		" Automatically save before commands like :next and :make
set hidden              " Hide buffers when they are abandoned
EOV

# ...and /root/.bashrc
cat <<EOB > /root/.bashrc
export LS_OPTIONS='--color=auto'
alias ls='ls \$LS_OPTIONS'
alias ll='ls \$LS_OPTIONS -l'
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
EOB

# /vagrant dir
mkdir /vagrant
chown -R vagrant:vagrant /vagrant

# vagrant ssh key
umask 077
mkdir -p ~vagrant/.ssh 
wget -q https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub -O ~vagrant/.ssh/authorized_keys
chown -R vagrant:vagrant ~vagrant/.ssh

