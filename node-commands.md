brew list nvm

If it’s installed, you should see output like:


brew --prefix nvm

This will return the correct path, usually something like:
/opt/homebrew/opt/nvm


echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.zshrc
echo '[ -s "$(brew --prefix nvm)/nvm.sh" ] && \. "$(brew --prefix nvm)/nvm.sh"' >> ~/.zshrc
echo '[ -s "$(brew --prefix nvm)/etc/bash_completion" ] && \. "$(brew --prefix nvm)/etc/bash_completion"' >> ~/.zshrc
source ~/.zshrc


nvm --version
which nvm


It should return something like:
/opt/homebrew/bin/nvm
