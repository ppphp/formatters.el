# formatters.el - An irresponsible formatter tool

This is an on-save formatter emacs extension, inspired by [go-mode](https://github.com/dominikh/go-mode.el), [prettier-emacs](https://github.com/prettier/prettier-emacs/blob/master/prettier-js.el), [lsp-mode](https://github.com/emacs-lsp/lsp-mode) and [emacs-format-all-the-code](https://github.com/lassik/emacs-format-all-the-code).

## usage

command + mode hook

## configure

Format just like gofmt, just configure formatter command.

```elisp
(require 'formatters)

(formatters-register-client
 (make-formatters-client :command "goimports" :args '("-w" "${file}") :mode 'go-mode)
 )


(add-hook 'go-mode-hook #'formatters)
(add-hook 'before-save-hook 'formatters-before-save)
```


