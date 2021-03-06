;; Integration of NEI with thing-at-point in order to make thing-at-point
;; aware of markdown and code cells. Symbols supported are nei-cell,
;; nei-code-cell and nei-markdown-cell
;;
;; The bounds at point functions are defined first as the forward
;; functions often make use of them.
;;
;; This approach is designed to help NEI be agnostic towards the exact
;; text format. The thing-at-point API is then used by the rest of NEI
;; mode.
;;
;; Defines aliases for things like (forward-thing 'nei-code-cell) with
;; functions such as nei-move-point-to-next-code-cell. Also includes
;; hook to display code and markdown overlays highlighting the cell
;; bounds.


(require 'nei-util)

(defvar nei--prompt-regexp "^# In\\[\\([\\[:alnum:] ]*\\)\]"
  "The regular expression used to match prompts. Not to be changed by users.")

(defvar nei--md-close-regexp "^\"\"\" #:md:$")

(defface nei-cell-highlight-code-face
  `((((class color) (background light)) :background
     ,(nei--average-with-background-color "white" 16))
    (((class color) (background  dark)) :background
     ,(nei--average-with-background-color "white" 16)))
  "Face for highlighting the code current cell.")

 
(defface nei-cell-highlight-markdown-face
  `((((class color) (background light)) :background
     ,(nei--average-with-background-color "black" 16))
    (((class color) (background  dark)) :background
     ,(nei--average-with-background-color "black" 16)))
  "Face for highlighting the code current cell.")

(defvar nei--highlight-overlay nil
  "The overlay used to highlight current cell in nei")


;;
;; Bounds of things (markdown and code cells)
;;

(defun nei--bounds-of-markdown-cell-at-point ()
  "Function to return bounds of markdown cell at point to integrate with thing-at-point"
  ;; Works by checking for end marker, looking forward for opening and
  ;; checking no triple quotes exist in between.
  (let ((end   (save-excursion  (progn (beginning-of-visual-line)
                                       (re-search-forward nei--md-close-regexp nil t 1))))
        (start (save-excursion  (progn (end-of-visual-line)
                                       (re-search-backward "^\"\"\"$" nil t 1)))))
    (if (not (null end))
        (save-excursion
          (goto-char end)
          (let ((intermediate (re-search-backward "\"\"\"" nil t 2)))
            (if (and (not (null start))
                     (not (null intermediate))
                     (<= intermediate start))
                (cons start end)
              )
            )
          )
      )
    )
  )

(defun nei--bounds-of-code-cell-at-point ()
  "Function to return bounds of code cell at point to integrate with thing-at-point"
  ;; If in a markdown cell, then not in a code cell
  (if (not (bounds-of-thing-at-point 'nei-markdown-cell))
      (let* ((next-md-bounds (save-excursion
                              (forward-thing 'nei-markdown-cell)
                              (bounds-of-thing-at-point 'nei-markdown-cell)))
            (prev-md-bounds (save-excursion
                              (forward-thing 'nei-markdown-cell -1)
                              (bounds-of-thing-at-point 'nei-markdown-cell)))
            (md-min-limit (or (cdr prev-md-bounds) 0))
            (md-max-limit (if (not (null next-md-bounds))
                              (- (car next-md-bounds) 1) (point-max)))
            (start-code (progn (save-excursion
                                 (end-of-visual-line)
                                 (re-search-backward nei--prompt-regexp nil t 1))))
            (next-code (progn (save-excursion
                                (end-of-visual-line)
                                (if (re-search-forward nei--prompt-regexp nil t 1)
                                    (progn
                                      (beginning-of-visual-line)
                                      (- (point) 1))))))
            (end (min (or next-code (point-max)) (or md-max-limit (point-max)))))
        (if (and (not (null start-code)) (< md-min-limit start-code))
            (progn
              (cons start-code end)
              )
          )
        )
    )
  )

(defun nei--bounds-of-cell-at-point ()
  "Function to return bounds of cell at point to integrate with thing-at-point"
  (or (nei--bounds-of-markdown-cell-at-point) (nei--bounds-of-code-cell-at-point))
  )


;;
;; Forward things (markdown and code cells)
;;

(defun re-search-forward-thing (regexp thing &optional bound noerror steps not-thing)
  "Utility similar to re-search-forward that only registers a match if
  there is thing at the position of the regexp match (as determined by
  bounds-of-thing-at-point). If not-thing is true, registers a match
  only if the thing is *not* present.

  Sets the point to the end of the occurrence found, and return point."
  (let* ((counter 0)
         (steps (if (null steps) 1 steps))
         (target-count (abs steps))
         (delta (if (< steps 0) -1 1))
         (position nil)
         (continue-search t))

    (save-excursion
      (while continue-search
        (setq position (re-search-forward regexp bound noerror delta))
        (if (and (not not-thing) (bounds-of-thing-at-point thing))
            (setq counter (+ 1 counter))
          )
        (if (and not-thing (not (bounds-of-thing-at-point thing)))
            (setq counter (+ 1 counter))
          )

        (if (or (eq position nil) (eq counter target-count))
            (setq continue-search nil))

        )
      )
    (if (not (null position))
        (progn
          (goto-char position)
          position
          )
      )
    )
  )


(defun nei--forward-markdown-cell (&optional arg)
  "Move point forward ARG markdown cells (backwards is ARG is negative).
   Returns t if the point is moved else nil."
    (let* ((target-pos nil)
           (arg (or arg 1))
           ;; If re-searching forward from inside an md cell, the next end boundary
           ;; is still within that cell. skips adds an offset to arg to compensate
           ;; which is not needed if arg is negative (jumping backwards)
           (skips (+ arg (if (bounds-of-thing-at-point 'nei-markdown-cell)
                             (if (> 0 arg) 0 1) 0)))
           (match (save-excursion
                    (re-search-forward-thing nei--md-close-regexp
                                             'nei-markdown-cell nil t skips))))
      (if match
          (progn
            (goto-char match)
            (let ((bounds (bounds-of-thing-at-point 'nei-markdown-cell)))
              (if bounds
                  (setq target-pos (+ (car bounds) 4))
                )
              )
            )
        )
      (if target-pos (progn (goto-char target-pos) t))
      )
    )


(defun nei--forward-code-cell (&optional arg)
  "Move point forward ARG code cells (backwards is ARG is negative).
   Returns t if the point is moved else nil."
  (let* ((within-code-cell (not (null (nei--bounds-of-code-cell-at-point))))
         (skips (if (and (< arg 0) within-code-cell) (- arg 1) arg))
         (match-pos (save-excursion
                      (re-search-forward-thing nei--prompt-regexp
                                               'nei-markdown-cell
                                               nil t
                                               skips t))))
    (if match-pos
        (if (< arg 0)
            (progn
              (goto-char (+
                          (save-excursion
                            (goto-char match-pos)
                            (end-of-visual-line)
                            (point)) 1))
              t)
          (progn (goto-char (+ 1 match-pos)) t)
          
          )
      )
    )
  )

(defun nei--forward-cell (&optional arg)
  "Move point forward ARG cells (backwards is ARG is negative).
   Returns t if the point is moved else nil."  
  (let* ((target-pos nil)
        (arg (or arg 1))
        (next-md nil)
        (next-code nil)
        (delta (if (< arg 0) -1 1))
        )

    (save-excursion
      (dotimes (x (abs arg))
        (setq next-md (save-excursion (if (nei--forward-markdown-cell delta) (point))))
        (setq next-code (save-excursion (if (nei--forward-code-cell delta) (point))))

        (cond ((and (null next-md) (null next-code))
               (setq target-pos nil))
              ((and next-md next-code)
               (setq target-pos
                     (if (eq delta -1) (max next-md next-code) (min next-md next-code))
                     ))
              (next-md (setq target-pos next-md))
              (next-code (setq target-pos next-code)))

        (if target-pos (goto-char target-pos))
        )
      )

    (if target-pos (progn (goto-char target-pos) t))
    )
  )


(defun nei--register-things-at-point ()
  ;; Markdown cells
  (put 'nei-markdown-cell 'bounds-of-thing-at-point
       'nei--bounds-of-markdown-cell-at-point)
  (put 'nei-markdown-cell 'forward-op
       'nei--forward-markdown-cell)
  ;; Code cells
  (put 'nei-code-cell 'bounds-of-thing-at-point
       'nei--bounds-of-code-cell-at-point)
  (put 'nei-code-cell 'forward-op
       'nei--forward-code-cell)
  ;; Both types of cell
  (put 'nei-cell 'bounds-of-thing-at-point
       'nei--bounds-of-cell-at-point)
  (put 'nei-cell 'forward-op
       'nei--forward-cell)
  )
  

;; Highlighting of bounds with overlay

(defun nei--update-highlight-thing (thing)
  (if (null mark-active)
      (let* ((cell-bounds (bounds-of-thing-at-point thing))
             (beginning (car cell-bounds))
             (end (cdr cell-bounds)))
        (if (and beginning end)
            (progn
              (move-overlay nei--highlight-overlay beginning end)
              (if (eq thing 'nei-code-cell)
                  (overlay-put nei--highlight-overlay 'face 'nei-cell-highlight-code-face)
                (overlay-put nei--highlight-overlay 'face 'nei-cell-highlight-markdown-face))
              )
          )
        )
    )
  )

(defun nei--update-highlight-cell ()
  "Uses regular expression search forwards/backwards to highlight
   the current cell with an overlay"
  (nei--update-highlight-thing 'nei-code-cell)
  (nei--update-highlight-thing 'nei-markdown-cell)
  )


(defun nei--point-move-disable-highlight-hook ()
  "Post-command hook to disable cell highlight when the
   point moves out the current overlay region"
  (if (and (memq this-command '(next-line previous-line))
           (not (null nei--highlight-overlay))
           (eq (current-buffer) (overlay-buffer nei--highlight-overlay)))
      (if (or (< (point) (overlay-start nei--highlight-overlay))
              (> (point) (overlay-end nei--highlight-overlay)))
          (move-overlay nei--highlight-overlay 0 0)
        )
    )
  )

;; Boundaries in region

(defun nei--cell-boundaries-in-region () ;; TODO char-mode option arg and do lines
  "Returns the boundaries of all the cells within a marked region"
  (save-mark-and-excursion 
    (let ((start (region-beginning))
          (end (region-end))
          (accumulator nil)
          (continue t))

      (goto-char start)
      (while continue
        (if (null (thing-at-point 'nei-cell)) (forward-thing 'nei-cell))
        (let ((bounds (bounds-of-thing-at-point 'nei-cell)))
          (if (and (>= (car bounds) start) (<= (cdr bounds) end))
              (push bounds accumulator))
          (if (>= (cdr bounds) end) (setq continue nil))
          
          )
        (forward-thing 'nei-cell)
        )
      (reverse accumulator)
      )
    )
  )

(defun nei--closest-boundary-to-point ()
  "Returns nil if at boundary already, 1 if the closest boundary is the
   next boundary, -1 if closest boundary is the previous boundary"
  (let ((bounds (bounds-of-thing-at-point 'nei-cell)))
    (if bounds
        (let ((back-distance (- (point) (car bounds)))
              (forward-distance (- (cdr bounds) (point))))
          (if (> back-distance forward-distance) 1 -1)
          )
      )
    )
  )
    
(defun nei--move-point-to-boundary (&optional mode)
  "Leaves the point in place if already at a boundary or moves it to the
   previous or next boundary according to mode. If mode is nil, the
   closest boundary is used, 1 always uses the next boundary and -1
   always uses the previous boundary. Returns the direction travelled."
  (let ((direction (if (null mode) (nei--closest-boundary-to-point) mode))
        (bounds (bounds-of-thing-at-point 'nei-cell)))
    (if (eq direction 1)
        (goto-char (min (point-max) (+ (cdr bounds) 1))))
    (if (eq direction -1)
        (goto-char (max (point-min) (- (car bounds) 1))))
    )
  )


;; Movement aliases

(defun nei-move-point-to-next-cell ()
  "Move the point to the next cell"
  (interactive)
  (forward-thing 'nei-cell)
)

(defun nei-move-point-to-previous-cell ()
  "Move the point to the previous cell"
  (interactive)
  (forward-thing 'nei-cell -1)
  )

(defun nei-move-point-to-next-code-cell ()
  "Move the point to the next cell"
  (interactive)
  (forward-thing 'nei-code-cell)
)

(defun nei-move-point-to-previous-code-cell ()
  "Move the point to the previous cell"
  (interactive)
  (forward-thing 'nei-code-cell -1)
  )

(defun nei-move-point-to-next-markdown-cell ()
  "Move the point to the next cell"
  (interactive)
  (forward-thing 'nei-markdown-cell)
)

(defun nei-move-point-to-previous-markdown-cell ()
  "Move the point to the previous cell"
  (interactive)
  (forward-thing 'nei-markdown-cell -1)
)

(provide 'nei-at-point)
