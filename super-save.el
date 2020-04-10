;;; super-save.el --- Auto-save buffers, based on your activity. -*- lexical-binding: t -*-

;; Copyright © 2015-2018 Bozhidar Batsov <bozhidar@batsov.com>

;; Author: Bozhidar Batsov <bozhidar@batsov.com>
;; URL: https://github.com/bbatsov/super-save
;; Keywords: convenience
;; Version: 0.3.0
;; Package-Requires: ((emacs "24.4"))

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:
;;
;; super-save saves buffers when they lose focus.
;; @see https://emacs-china.org/t/topic/7687
;;
;;; Code:

(defgroup super-save nil
  "Smart-saving of buffers."
  :group 'tools
  :group 'convenience)

(defvar super-save-mode-map (make-sparse-keymap)
  "super-save mode's keymap.")

(defcustom super-save-triggers
  '(switch-to-buffer other-window windmove-up windmove-down windmove-left windmove-right next-buffer previous-buffer)
  "A list of commands which would trigger `super-save-command'."
  :group 'super-save
  :type '(repeat symbol)
  :package-version '(super-save . "0.1.0"))

(defcustom super-save-hook-triggers
  '(mouse-leave-buffer-hook focus-out-hook)
  "A list of hooks which would trigger `super-save-command'."
  :group 'super-save
  :type '(repeat symbol)
  :package-version '(super-save . "0.3.0"))

(defcustom super-save-auto-save-when-idle nil
  "Save current buffer automatically when Emacs is idle."
  :group 'super-save
  :type 'boolean
  :package-version '(super-save . "0.2.0"))

(defcustom super-save-idle-duration 5
  "The number of seconds Emacs has to be idle, before auto-saving the current buffer.
See `super-save-auto-save-when-idle'."
  :group 'super-save
  :type 'integer
  :package-version '(super-save . "0.2.0"))

(defcustom super-save-remote-files t
  "Save remote files when t, ignore them otherwise."
  :group 'super-save
  :type 'boolean
  :package-version '(super-save . "0.3.0"))

(defcustom super-save-all-files t
  "Save all buffer when t, ignore them otherwise."
  :group 'super-save
  :type 'boolean
  :package-version '(super-save . "0.3.0"))

(defcustom super-save-exclude nil
    "A list of regexps for buffer-file-name excluded from super-save.
When a buffer-file-name matches any of the regexps it is ignored."
  :group 'super-save
  :type '(repeat (choice regexp))
  :package-version '(super-save . "0.4.0"))

(defcustom super-save-silent-p t
  "Not prompted to save information when t, ignore them otherwise,"
  :group 'super-save
  :type 'boolean
  :package-version '(super-save . "0.4.0"))

(defcustom super-save-all-buffer-p t
  "Save all buffer before exiting emacs when t, ignore theme otherwise,"
  :group 'super-save
  :type 'boolean
  :package-version '(super-save . "0.4.0"))

(defun super-save-include-p (filename)
  "Return non-nil if FILENAME doesn't match any of the `super-save-exclude'."
  (let ((checks super-save-exclude)
        (keepit t))
    (while (and checks keepit)
      (setq keepit (not (ignore-errors
                          (if (stringp (car checks))
                              (string-match (car checks) filename))))
            checks (cdr checks)))
    keepit))

(defun super-save-command ()
  "Save the current buffer if needed."
  (let ((buffer-to-save (if super-save-all-files
                            (buffer-list)
                          (list (current-buffer)))))
    (dolist (buf buffer-to-save)
      (set-buffer buf)
      (when (and buffer-file-name
                 (buffer-modified-p (current-buffer))
                 (file-writable-p buffer-file-name)
                 (if (file-remote-p buffer-file-name) super-save-remote-files t)
                 (super-save-include-p buffer-file-name)
                 (or (not (boundp 'yas--active-snippets)) ; Yassnippet is not active?
                     (not yas--active-snippets))
                 (or (not (boundp 'company-candidates)) ; Company is not active?
                     (not company-candidates)))
        (if super-save-silent-p
            (with-temp-message
                (with-current-buffer " *Minibuf-0*" (buffer-string))
              (let ((inhibit-message t))
                (save-buffer)))
          (save-buffer))))))

(defvar super-save-idle-timer)

(defun super-save-command-advice (&rest _args)
  "A simple wrapper around `super-save-command' that's advice-friendly."
  (super-save-command))

(defun super-save-advise-trigger-commands ()
  "Apply super-save advice to the commands listed in `super-save-triggers'."
  (mapc (lambda (command)
          (advice-add command :before #'super-save-command-advice))
        super-save-triggers))

(defun super-save-remove-advice-from-trigger-commands ()
  "Remove super-save advice from to the commands listed in `super-save-triggers'."
  (mapc (lambda (command)
          (advice-remove command #'super-save-command-advice))
        super-save-triggers))

(defun super-save-initialize-idle-timer ()
  "Initialize super-save idle timer if `super-save-auto-save-when-idle' is true."
  (setq super-save-idle-timer
        (when super-save-auto-save-when-idle
          (run-with-idle-timer super-save-idle-duration t #'super-save-command))))

(defun super-save-stop-idle-timer ()
  "Stop super-save idle timer if `super-save-idle-timer' is set."
  (when super-save-idle-timer
    (cancel-timer super-save-idle-timer)))

(defun super-save-initialize ()
  "Setup super-save's advices and hooks."
  (super-save-advise-trigger-commands)
  (super-save-initialize-idle-timer)
  (dolist (hook super-save-hook-triggers)
    (add-hook hook #'super-save-command))
  (when super-save-all-buffer-p
    (advice-add 'save-buffers-kill-emacs :before #'super-save-all-buffer-a)))

(defun super-save-stop ()
  "Cleanup super-save's advices and hooks."
  (super-save-remove-advice-from-trigger-commands)
  (super-save-stop-idle-timer)
  (dolist (hook super-save-hook-triggers)
    (remove-hook hook #'super-save-command))
  (when super-save-all-buffer-p
    (advice-remove 'save-buffers-kill-emacs #'super-save-all-buffer-a)))

;;;###autoload
(defun super-save-all-buffer ()
  (interactive)
  (let ((super-save-all-files t)
        (super-save-silent-p t))
    (super-save-command)))

(defun super-save-all-buffer-a (&rest _)
  (super-save-all-buffer))

;;;###autoload
(define-minor-mode super-save-mode
  "A minor mode that saves your Emacs buffers when they lose focus."
  :lighter " super-save"
  :keymap super-save-mode-map
  :group 'super-save
  :global t
  (if super-save-mode
      (super-save-initialize)
    (super-save-stop)))

(provide 'super-save)
;;; super-save.el ends here
