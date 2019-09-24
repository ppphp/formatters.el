;;; formatters.el --- an irresponsible formatter tool -*- lexical-binding: t -*-

;; Author: ppphp
;; Created: 7 October 2019
;; Url: https://github.com/ppphp/formatters.el
;; Keywords: languages

;; This file is not part of GNU Emacs.

;;; Commentary:
;; generate your code formatter client.

;;; Code:

(require 'cl-lib)
(require 's)

(defgroup formatters nil
  "Format your emacs buffer."
  :group 'languages)

(cl-defstruct formatters--client
  (mode nil)
  (command nil)
  (args nil)
)

(defvar formatters-clients (make-hash-table :test 'eql)
  "Hash table mode -> client.
It contains all of the clients that are currently registered.")

(defun formatters-register-client (client)
  "Register formatters client like lsp client CLIENT."
  (cl-assert (symbolp (formatters--client-mode client)) t)
  (puthash (formatters--client-mode client) client formatters-clients)
  )

(defalias 'make-formatters-client 'make-formatters--client)

(defvar-local formatters-local-client ()
  "A local formatter."
  )

(defun formatters--goto-line (line)
  "LINE."
  (goto-char (point-min))
  (forward-line (1- line)))

(defun formatters--apply-rcs-patch (patch-buffer)
  "Apply an RCS-formatted diff from PATCH-BUFFER to the current buffer."
  (let ((target-buffer (current-buffer))
        (line-offset 0)
        (column (current-column)))
    (save-excursion
      (with-current-buffer patch-buffer
        (goto-char (point-min))
        (while (not (eobp))
          (unless (looking-at "^\\([ad]\\)\\([0-9]+\\) \\([0-9]+\\)")
            (error "Invalid rcs patch or internal error in formatters--apply-rcs-patch"))
          (forward-line)
          (let ((action (match-string 1))
                (from (string-to-number (match-string 2)))
                (len  (string-to-number (match-string 3))))
            (cond
             ((equal action "a")
              (let ((start (point)))
                (forward-line len)
                (let ((text (buffer-substring start (point))))
                  (with-current-buffer target-buffer
                    (cl-decf line-offset len)
                    (goto-char (point-min))
                    (forward-line (- from len line-offset))
                    (insert text)))))
             ((equal action "d")
              (with-current-buffer target-buffer
                (formatters--goto-line (- from line-offset))
                (cl-incf line-offset len)
                (formatters--delete-whole-line len)))
             (t
              (error "Invalid rcs patch or internal error in go--apply-rcs-patch")))))))
    (move-to-column column)))

(defun formatters--delete-whole-line (&optional arg)
  "Delete the current line without putting it in the `kill-ring'.
Derived from function `kill-whole-line'.  ARG is defined as for that
function."
  (setq arg (or arg 1))
  (if (and (> arg 0)
           (eobp)
           (save-excursion (forward-visible-line 0) (eobp)))
      (signal 'end-of-buffer nil))
  (if (and (< arg 0)
           (bobp)
           (save-excursion (end-of-visible-line) (bobp)))
      (signal 'beginning-of-buffer nil))
  (cond ((zerop arg)
         (delete-region (progn (forward-visible-line 0) (point))
                        (progn (end-of-visible-line) (point))))
        ((< arg 0)
         (delete-region (progn (end-of-visible-line) (point))
                        (progn (forward-visible-line (1+ arg))
                               (unless (bobp)
                                 (backward-char))
                               (point))))
        (t
         (delete-region (progn (forward-visible-line 0) (point))
                        (progn (forward-visible-line arg) (point))))))

(defcustom formatters-show-errors 'buffer
  "Where to display fmt error output.
It can either be displayed in its own buffer, in the echo area, or not at all.

Please note that Emacs outputs to the echo area when writing
files and will overwrite gofmt's echo output if used from inside
a `before-save-hook'."
  :type '(choice
          (const :tag "Own buffer" buffer)
          (const :tag "Echo area" echo)
          (const :tag "None" nil))
  :group 'formatters)

(defun formatters--kill-error-buffer (errbuf)
  "ERRBUF."
  (let ((win (get-buffer-window errbuf)))
    (if win
        (quit-window t win)
      (kill-buffer errbuf))))

(defalias 'formatters--file-local-name
  (if (fboundp 'file-local-name) #'file-local-name
    (lambda (file) (or (file-remote-p file 'localname) file))))

(defun formatters--process-errors (filename tmpfile errbuf)
  "FILENAME TMPFILE ERRBUF."
  (with-current-buffer errbuf
    (if (eq formatters-show-errors 'echo)
        (progn
          (message "%s" (buffer-string))
          (formatters--kill-error-buffer errbuf))
      ;; Convert the gofmt stderr to something understood by the compilation mode.
      (goto-char (point-min))
      (if (save-excursion
            (save-match-data
              (search-forward "flag provided but not defined: -srcdir" nil t)))
          (insert "Your version of goimports is too old and doesn't support vendoring. Please update goimports!\n\n"))
      (insert "formatters errors:\n")
      (let ((truefile
                 (concat (file-name-directory filename) (file-name-nondirectory tmpfile))
               ))
        (while (search-forward-regexp
                (concat "^\\(" (regexp-quote (formatters--file-local-name truefile))
                        "\\):")
                nil t)
          (replace-match (file-name-nondirectory filename) t t nil 1)))
      (compilation-mode)
      (display-buffer errbuf))))

(defun formatters--lazy-list(lst)
  "LST: Original list to recover symbol to value."
  (if (listp lst) (
		   message lst
		   ) (error "Lst should be a list")
   )
  )

(defun formatters-current-buffer()
  "Format current buffer."
  (interactive)
  (let* ((ext (file-name-extension buffer-file-name t))
	(tmpfile (make-nearby-temp-file "formatters" nil ext))
        (patchbuf (get-buffer-create "*Formatter patch*"))
        (errbuf (if formatters-show-errors (get-buffer-create "*Formatter Errors*")))
        (coding-system-for-read 'utf-8)
        (coding-system-for-write 'utf-8)
	)

    ;; ensure closing buffers created above.
    (unwind-protect
        (save-restriction
          (widen)
          (if errbuf
              (with-current-buffer errbuf
                (setq buffer-read-only nil)
                (erase-buffer)))
          (with-current-buffer patchbuf
            (erase-buffer))
          (write-region nil nil tmpfile)
	  (message "%s" (formatters--client-args formatters-local-client))
	  (setq-local our-formatters-args '())
	  (dolist
	      (arg (formatters--client-args formatters-local-client))
	    (setq our-formatters-args (cons (s-format arg (lambda (a) tmpfile)) our-formatters-args))
	    )
	  (setq our-formatters-args (reverse our-formatters-args))
	  (message "%s" our-formatters-args)
          (message "Calling formatters: %s %s" (formatters--client-command formatters-local-client) our-formatters-args)
          ;; We're using errbuf for the mixed stdout and stderr output. This
          ;; is not an issue because gofmt -w does not produce any stdout
          ;; output in case of success.
          (if (zerop (apply #'process-file  (formatters--client-command formatters-local-client) nil errbuf nil our-formatters-args))
              (progn
                ;; There is no remote variant of ‘call-process-region’, but we
                ;; can invoke diff locally, and the results should be the same.
                (if (zerop (let ((local-copy (file-local-copy tmpfile)))
                             (unwind-protect
                                 (call-process-region
                                  (point-min) (point-max) "diff" nil patchbuf
                                  nil "-n" "-" (or local-copy tmpfile))
                               (when local-copy (delete-file local-copy)))))
                    (message "Buffer is already formatted")
                  (formatters--apply-rcs-patch patchbuf)
                  (message "Applied fmt"))
                (if errbuf (formatters--kill-error-buffer errbuf)))
            (message "Could not apply fmt")
	    (if errbuf (formatters--process-errors (buffer-file-name) tmpfile errbuf)))
	  )
      (kill-buffer patchbuf)
      (delete-file tmpfile)))
  )


(defun formatters-before-save ()
  "Add this to .emacs to run gofmt on the current buffer when saving:
\(add-hook 'before-save-hook 'gofmt-before-save).

Note that this will cause ‘go-mode’ to get loaded the first time
you save any file, kind of defeating the point of autoloading."

  (interactive)
  (when formatters-local-client (formatters-current-buffer)))

;;;###autoload
(defun formatters ()
  "ARG."
  (interactive)
  (setq-local formatters-local-client (gethash major-mode formatters-clients))
  )
(provide 'formatters)
;;; formatters.el ends here
