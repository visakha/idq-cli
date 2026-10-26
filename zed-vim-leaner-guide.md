# About
I want to use Zed as my main editor for Leaner, but I want to make sure I have a good understanding of how to use it effectively. This guide will cover the basics of using Zed for Leaner development, including setup, key features, and tips for productivity.


# References
- [gist] (https://gist.github.com/therealparmesh/f6d404a25591325cc9d8598f815cd265)
- [Zed Editor Documentation] (https://docs.zed.dev/)
- 

# Setup
1. **Install Zed**: Download and install Zed from the official website.

# task: Insert a line above the current line
To insert a line above your current line while using Vim mode in the Zed Editor, use the following standard Vim commands:
• From Normal Mode: Press Shift + O (or capital O). This creates a new empty line above your current line and automatically switches your editor into Insert mode.
• From Insert Mode: Press Ctrl + O, then O. This invokes a temporary single-shot Normal mode command to open the line above without permanently exiting Insert mode.

Custom Binding (Without changing modes)

If you want to map a keyboard shortcut to insert a line above without forcing yourself into standard Vim insertion behaviors, you can add a custom shortcut to your Zed keymap.json:
```json
[
  {
    "context": "Editor && vim_mode == normal",
    "bindings": {
      "cmd-shift-enter": "vim::InsertLineAbove"
    }
  }
]
```


