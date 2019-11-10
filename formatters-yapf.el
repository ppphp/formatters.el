
(require 'formatters)

(formatters-register-client
 (make-formatters-client :command "yapf" :args '("-i" "${file}") :mode 'python-mode)
 )

(provide 'formatters-yapf)
