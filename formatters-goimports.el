
(require 'formatters)

(formatters-register-client
 (make-formatters-client :command "goimports" :args '("-w" "${file}") :mode 'go-mode)
 )

(provide 'formatters-goimports)
