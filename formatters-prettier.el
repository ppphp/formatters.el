
(require 'formatters)

(formatters-register-client
 (make-formatters-client :command "prettier" :args '("--write" "${file}") :mode 'js-mode)
 )
(formatters-register-client
 (make-formatters-client :command "prettier" :args '("--write" "${file}") :mode 'typescript-mode)
 )

(provide 'formatters-prettier)
