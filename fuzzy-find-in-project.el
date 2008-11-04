;; fuzzy-find-in-project.el - Emacs binding to the `fuzzy_file_finder' rubygem.

;; Author: Justin Weiss
;; URL: http://github.com/avvo/fuzzy-find-in-project/tree/master
;; Version: 1.0
;; Created: 2008-10-14
;; Keywords: project, convenience
 
;; This file is NOT part of GNU Emacs.
 
;;; License:
 
;; Copyright (c) 2008 Justin Weiss
;;
;; Permission is hereby granted, free of charge, to any person
;; obtaining a copy of this software and associated documentation
;; files (the "Software"), to deal in the Software without
;; restriction, including without limitation the rights to use,
;; copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the
;; Software is furnished to do so, subject to the following
;; conditions:
;;
;; The above copyright notice and this permission notice shall be
;; included in all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
;; OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
;; HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
;; WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;; FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
;; OTHER DEALINGS IN THE SOFTWARE.

;;; Commentary: 

;; Requires ruby, rubygems, and the `fuzzy_file_finder' rubygem. 
;;
;; The `fuzzy_file_finder' rubygem can be installed with the following command: 
;; `sudo gem install --source http://gems.github.com jamis-fuzzy_file_finder'

;;; Usage:
;; The primary interface into the functionality provided by this file is through
;; the `fuzzy-find-in-project' function. Calling this function will match the query to 
;; the files under `fuzzy-find-project-root' and open up a completion buffer with
;; the first matched file selected (with a `> '.) The selection can be changed using
;; `C-n' and `C-p', and the currently selected file can be opened using `<RET>'. 

;;; Configuration:
;; In your .emacs or init.el: 
;;
;; (add-to-list 'load-path "~/.emacs.d/path/to/fuzzy-find-in-project")
;; (require 'fuzzy-find-in-project)
;; (fuzzy-find-project-root "~/path/to/project")

;;; TODO: 
;; - Clean up *Completions* buffer on exit
;; - Use project-local-variables to scope the find to the current file's project
;; - misc. cleanup and error handling (make sure process is killed on failure, etc.)

;;; Code:

(defvar fuzzy-find-project-root "."
  "The root directory in which to recursively look for files")

(defun fuzzy-find-project-root (root)
  "Sets the new fuzzy find project root."
  (interactive "DSet fuzzy finder project root: ")
  (setq fuzzy-find-project-root root))

(defvar fuzzy-find-initialized nil
  "Tracks whether or not the fuzzy finder has been initialized.")

(defvar fuzzy-find-completion-buffer-name "*Completions*"
  "The name of the buffer to display the possible file name completions")

(defvar fuzzy-find-mode nil
  "Tells the minibuffer when to use the fuzzy finder")

(defvar fuzzy-find-process nil
  "Holds the process that runs the fuzzy_find_file rubygem")

(defvar fuzzy-find-completions ""
  "Contains the current file name completions")

(defvar fuzzy-find-selected-completion-index 1
  "1-based index of the currently selected completion")

(defvar fuzzy-find-in-project-setup-hook nil
  "Hook that runs after fuzzy-find-in-project initialization")

(defun fuzzy-find-file (process query) 
  "Communicates with the fuzzy find gem, sending the query string `query' and retrieves the possible completions as a string."
  (setq fuzzy-find-completions "")
  (process-send-string process (concat query "\n"))
  (let ((count 0)) 
    (while (and (not (string-ends-with-p fuzzy-find-completions "\nEND\n")) (> 200 count))
      (sleep-for 0 10)
      (setq count (1+ count))))
  (setq fuzzy-find-completions (string-trim-end fuzzy-find-completions (length "\nEND\n")))
  fuzzy-find-completions)

(defun string-trim-end (string num-chars)
  "Trims `num-chars' from the end of `string'. Returns the empty string if `num-chars' is larger than the length of `string'."
  (if (< num-chars (length string))
    (substring string 0 (- (length string) num-chars))
    ""))

(defun string-ends-with-p (string suffix)
  "Determines whether the string `string' ends with the suffix `suffix'."
  (let ((string-length (length string))
        (suffix-length (length suffix)))
    (cond
     ((> suffix-length string-length) 
      nil)
     (t 
      (let ((start-index (- string-length suffix-length)))
        (string= (substring string start-index string-length)
                 suffix))))))

(defun string-begins-with-p (string substring)
  "Determines whether the string `string' begins with the substring `substring'."
  (cond
   ((> (length substring) (length string))
    nil)
   (t
    (string= (substring string 0 (length substring)) substring))))

(defun fuzzy-find-get-completions (process output)
  "The process filter for retrieving data from the fuzzy_file_finder ruby gem"
  (setq fuzzy-find-completions (concat fuzzy-find-completions output)))

(defun fuzzy-find-command-hook ()
  "A hook to fuzzy find whatever string is in the minibuffer following the prompt. 
Displays the completion list along with a selector in the `*Completions*' buffer. 
The hook runs on each command."
  (setq fuzzy-find-selected-completion-index 1)
  (let ((query-string (buffer-substring-no-properties (minibuffer-prompt-end) (point-max)))) 
    (get-buffer-create fuzzy-find-completion-buffer-name)
    (set-buffer fuzzy-find-completion-buffer-name)
    (let ((buffer-read-only nil))
      (erase-buffer)
      (insert (fuzzy-find-file fuzzy-find-process query-string))
      (fuzzy-find-mark-beginning-of-line fuzzy-find-selected-completion-index "> "))
    (goto-line fuzzy-find-selected-completion-index)
    (display-buffer fuzzy-find-completion-buffer-name)))

(defun fuzzy-find-in-project ()
  "The main function for finding a file in a project. 

This function opens a window showing possible completions for the letters typed into the minibuffer. By default the letters complete the file name; however, the finder can also complete on paths by typing a `/' into the minibuffer after the letters making up a path component. Move between selections using `C-n' and `C-p', and select a file to open using `<RET>'."
  (interactive)
  (setq fuzzy-find-mode t)
  (fuzzy-find-initialize)
  (add-hook 'minibuffer-setup-hook 'fuzzy-find-minibuffer-setup)
  (add-hook 'minibuffer-exit-hook 'fuzzy-find-minibuffer-exit)
  (run-hooks 'fuzzy-find-in-project-setup-hook)
  (setq fuzzy-find-process (start-process-shell-command "ffip" nil (locate-file "fuzzy-find-in-project.rb" load-path) fuzzy-find-project-root))
  (set-process-filter fuzzy-find-process 'fuzzy-find-get-completions)
  (read-string "Find file: ")
  (cond 
   ((eq fuzzy-find-exit 'find-file)
    (set-buffer fuzzy-find-completion-buffer-name)
    (let ((buffer-read-only nil))
      (fuzzy-find-unmark-beginning-of-line fuzzy-find-selected-completion-index "> "))
    (find-file (fuzzy-find-read-line fuzzy-find-selected-completion-index)))))

(defun fuzzy-find-minibuffer-setup ()
  "Setup hook for the minibuffer"
  (when (eq fuzzy-find-mode t)
    (add-hook 'post-command-hook 'fuzzy-find-command-hook nil t)
    (use-local-map fuzzy-find-keymap)))

(defun fuzzy-find-minibuffer-exit ()
  "Cleanup code when exiting the minibuffer"
  (when (eq fuzzy-find-mode t)
    (interrupt-process fuzzy-find-process)
    (use-local-map (keymap-parent fuzzy-find-keymap))
    (setq fuzzy-find-mode nil)))

(defun fuzzy-find-initialize ()
  "Initialize the keymap and other things that need to be setup before the first run of the fuzzy file finder."
  (if (not fuzzy-find-initialized) 
      (progn
        (setq fuzzy-find-keymap (make-sparse-keymap))
        (set-keymap-parent fuzzy-find-keymap minibuffer-local-map)
        (define-key fuzzy-find-keymap "\C-n" 'fuzzy-find-next-completion)
        (define-key fuzzy-find-keymap "\C-p" 'fuzzy-find-previous-completion)
        (define-key fuzzy-find-keymap "\r" 'fuzzy-find-select-completion)
        (setq fuzzy-find-initialized t))))
        
;;unwind-protect around main loop?

(defun fuzzy-find-read-line (line-number)
  "Reads line `line-number' from the current buffer."
  (save-excursion
    (goto-line line-number)
    (let ((begin-point (move-beginning-of-line nil))
          (end-point (progn (move-end-of-line nil) (point))))
      (buffer-substring-no-properties begin-point end-point))))

(defun fuzzy-find-select-completion ()
  "Selects the file at location `fuzzy-find-completion-index' and exits the minibuffer."
  (interactive)
  (setq fuzzy-find-exit 'find-file)
  (exit-minibuffer))

(defun fuzzy-find-mark-beginning-of-line (line-number tag)
  "Inserts tag `tag' from the beginning of line `line-number'"
  (save-excursion
    (goto-line line-number)
    (insert tag)))

(defun fuzzy-find-unmark-beginning-of-line (line-number tag)
  "Removes tag `tag' from the beginning of line `line-number' if it begins with `tag'."
  (save-excursion
    (goto-line line-number)
    (if (string-begins-with-p (fuzzy-find-read-line line-number) tag) 
        (delete-char (length tag)))))

(defun fuzzy-find-mark-completion (completion-index-delta)
  "Moves the completion index marker by `completion-index-delta' and marks the line corresponding to the currently selected completion."
  (set-buffer fuzzy-find-completion-buffer-name)
  (let ((buffer-read-only nil))
    (fuzzy-find-unmark-beginning-of-line fuzzy-find-selected-completion-index "> ")
    (setq fuzzy-find-selected-completion-index (+ completion-index-delta fuzzy-find-selected-completion-index))
    ;; reset completion index if it falls out of bounds
    (if (< fuzzy-find-selected-completion-index 1) (setq fuzzy-find-selected-completion-index 1))
    (if (> fuzzy-find-selected-completion-index (count-lines (point-min) (point-max))) (setq fuzzy-find-selected-completion-index (count-lines (point-min) (point-max))))
    (fuzzy-find-mark-beginning-of-line fuzzy-find-selected-completion-index "> "))
    (goto-line fuzzy-find-selected-completion-index)
    ;; make sure the window scrolls correctly
    (set-window-point (get-buffer-window fuzzy-find-completion-buffer-name) (point)))

(defun fuzzy-find-next-completion ()
  "Selects the next completion."
  (interactive)
  (fuzzy-find-mark-completion 1))
    
(defun fuzzy-find-previous-completion ()
  "Selects the previous completion."
  (interactive)
  (fuzzy-find-mark-completion -1))
    
(provide 'fuzzy-find-in-project)
