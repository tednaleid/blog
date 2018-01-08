---
title: Vim Movement Shortcuts Wallpaper
redirect_from: "/blog/2010/10/04/vim-movement-shortcuts-wallpaper"
---
I've recently moved back to vim (actually MacVim) after a 5 year hiatus using TextMate.  A big part of that move was inspired by Steve Losh's recent post <a href="http://stevelosh.com/blog/2010/09/coming-home-to-vim/">Coming Home to Vim</a> which has a number of really great tips.

I've cribbed many of them and have my <a href="http://bitbucket.org/tednaleid/vimrc">.vimrc / .vim</a> dotfiles checked into a public bitbucket repo.

There have been some big changes in the last 5 years since I've been away from vim (or else I just didn't know what the hell I was doing, which is also possible).  The addition of <a href="http://github.com/tpope/vim-pathogen">pathogen</a> for plugin management makes configuration much easier.  All plugins are completely contained in their own directory.  You can try something out and if it doesn't work, just delete the plugin's directory to uninstall it.

<a href="http://www.vim.org/scripts/script.php?script_id=1658">NerdTree</a> is nice, but <a href="http://peepcode.com/products/peepopen">PeepOpen</a>'s integration with MacVim for finding/opening files beats TextMate's cmd-T hands down.

I tend to be a hands-on, visual learner, so I looked around for a nice wallpaper to help me learn and retain the panoply of vim movement commands, but all I was able to find were simple lists of commands, so I decided to whip my own version up.

It shows all of the default movement commands, each command is placed relative to the center of the image and are ordered based on how far your cursor will likely travel.   All of these are active in vim's "normal" mode (though I believe most if not all of them will also work in "visual" mode.

I also find it useful to set my MacVim window to be slightly transparent so that I can see the shortcuts through the window if I need to.  In MacVim 7.3 you need to turn on the Advanced->"Use experimental renderer" option.  Then you can ":set transp=20" to make it 20% transparent (which feels right to me, but you might want to move it up/down depending on your preferences).

You can <a href="http://bitbucket.org/tednaleid/vim-shortcut-wallpaper/raw/tip/vim-shortcuts.png">download the full size (1900x1200)</a> (or <a href="http://bitbucket.org/tednaleid/vim-shortcut-wallpaper/raw/tip/vim-shortcuts2560x1600.png">2560x1600</a>) image for yourself.

<a href="http://bitbucket.org/tednaleid/vim-shortcut-wallpaper/raw/tip/vim-shortcuts.png"><img src="http://bitbucket.org/tednaleid/vim-shortcut-wallpaper/raw/tip/vim-shortcuts.png" alt="Vim Shortcuts Wallpaper" height="600"/></a>

I've also got the original OmniGraffle file that I used to create it <a href="http://bitbucket.org/tednaleid/vim-shortcut-wallpaper/src">checked in to a BitBucket repo</a> if anyone feels like remixing it or adding their own shortcuts or customizations to it.
