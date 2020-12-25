;;; svg-icon.el --- A library to create SVG icons on the fly -*- lexical-binding: t; -*-

;; Copyright (C) 2021 Nicolas .P Rougier

;; Author: Nicolas P. Rougier <nicolas.rougier@inria.fr>
;; URL: https://github.com/rougier/emacs-svg-icon
;; Keywords: multimedia
;; Version: 0.1

;; Package-Requires: ((emacs "27.1"))

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This library allows to create svg icons by parsing remote collections
;; whose license are compatibles with GNU Emacs:
;;
;; - Boxicons (https://github.com/atisawd/boxicons), available under a
;;   Creative Commons 4.0 license.  As of version 2.07 (December 2020),
;;   this collection offers 1500 icons in two styles (regular & solid).
;;   Gallery is available at https://boxicons.com/
;;
;; - Octicons (https://github.com/primer/octicons), available under a
;;   MIT License with some usage restriction for the GitHub logo.  As of
;;   version 11.2.0 (December 2020), this collection offers 201 icons.
;;   Gallery available at https://primer.style/octicons/
;;
;; - Material (https://github.com/Templarian/MaterialDesign),
;;   available under an Apache 2.0 license.  As of version 5.8.55
;;   (December 2020), this collection offers 5000+ icons in 4 styles
;;   (filled, outlined, rounded, sharp).  Gallery available at
;;   https://materialdesignicons.com/
;;
;; - Bootstrap (https://github.com/twbs/icons), available under an MIT
;;   license.  As of version 1.2.1 (December 2020), this collection
;;   offers 1200+ icons in 2 styles (regular & filled).  Gallery
;;   available at https://icons.getbootstrap.com/
;;
;; The default size of an icon is exactly 2x1 characters such that it
;; can be inserted inside a text without disturbing alignment.
;;
;; Note: Each icon is cached locally to speed-up loading the next time
;;       you use it.  If for some reason the cache is corrupted you can
;;       force reload using the svg-icon-get-data function.
;;
;; If you want to add new collections (i.e. URL), make sure the icons
;; are monochrome, their size is consistent.

;;; Code:
(require 'xml)
(require 'svg)
(require 'color)

(defgroup svg-icon nil
  "SVG icons collection created on the fly."
  :group 'multimedia)

(defcustom  svg-icon-collections
  '(("bootstrap" . "https://icons.getbootstrap.com/icons/%s.svg")
    ("material" . "https://raw.githubusercontent.com/Templarian/MaterialDesign/master/svg/%s.svg")
    ("octicons" . "https://raw.githubusercontent.com/primer/octicons/master/icons/%s-24.svg")
    ("boxicons" . "https://boxicons.com/static/img/svg/regular/bx-%s.svg"))
    
  "Various icons collections stored as (name . base-url).

The name of the collection is used as a pointer for the various
icon creation methods. The base-url is a string containing a %s
such that is can be replaced with the name of a specific icon.
User is responsible for finding/giving proper names for a given
collection (there are way too many to store them)."

  :type '(alist :key-type (string :tag "Name")
                :value-type (string :tag "URL"))
  :group 'svg-icon)


(defun svg-icon-get-data (collection name &optional force-reload)
  "Retrieve icon NAME from COLLECTION.

Cached version is returned if it exists unless FORCE-RELOAD is t."
  
  ;; Build url from collection and name without checking for error
  (let ((url (format (cdr (assoc collection svg-icon-collections)) name)))

    ;; Get data only if not cached or if explicitely requested
    (if (or force-reload (not (url-is-cached url)))
        (let ((url-automatic-caching t)
              (filename (url-cache-create-filename url)))
          (with-current-buffer (url-retrieve-synchronously url)
            (write-region (point-min) (point-max) filename))))

    ;; Get data from cache
    (let ((buffer (generate-new-buffer " *temp*")))
      (with-current-buffer buffer
        (url-cache-extract (url-cache-create-filename url)))
      (with-temp-buffer
        (url-insert-buffer-contents buffer url)
        (xml-parse-region (point-min) (point-max))))))

(defun svg-icon--emacs-color-to-svg-color (color-name)
  "Convert Emacs COLOR-NAME to #rrggbb form.
If COLOR-NAME is unknown to Emacs, then return COLOR-NAME as-is."
  (let ((rgb-color (color-name-to-rgb color-name)))
    (if rgb-color
        (apply #'color-rgb-to-hex (append rgb-color '(2)))
      color-name)))

(defun svg-icon (collection name &optional fg-color bg-color zoom)
  "Build the icon NAME from COLLECTION.

Icon is drawn using FG-COLOR (default is `default' face's foreground)
on a BG-COLOR background (default transparent). Optional integer ZOOM
level control the size of the icon. Default size is 2x1 characters.
FG-COLOR or BG-COLOR also could be a face.  In this case colors
specified in `:foreground' or `:background' attribute is used."
  
  (let* ((root (svg-icon-get-data collection name))

         ;; Read original viewbox
         (viewbox (cdr (assq 'viewBox (xml-node-attributes (car root)))))
         (viewbox (mapcar 'string-to-number (split-string viewbox)))
         (view-x (nth 0 viewbox))
         (view-y (nth 1 viewbox))
         (view-width (nth 2 viewbox))
         (view-height (nth 3 viewbox))

         ;; Set icon size (in pixels) to 2x1 characters
         (svg-width  (* (window-font-width)  2))
         (svg-height (* (window-font-height) 1))

         ;; Compute the new viewbox (adjust y origin and height)
         (ratio (/ view-width svg-width))
         (delta-h (ceiling (/ (- view-height (* svg-height ratio) ) 2)))
         (view-y (- view-y delta-h))
         (view-height (+ view-height (* delta-h 2)))

         ;; Zoom the icon by using integer factor only
         (zoom (max 1 (truncate (or zoom 1))))
         (svg-width  (* svg-width zoom))
         (svg-height (* svg-height zoom))

         (svg-viewbox (format "%f %f %f %f" view-x view-y view-width view-height))
         (fg-color (svg-icon--emacs-color-to-svg-color
                    (or (when (facep fg-color)
                          (face-foreground fg-color nil t))
                        fg-color (face-attribute 'default :foreground))))
         (bg-color (svg-icon--emacs-color-to-svg-color
                    (or (when (facep bg-color)
                          (face-background bg-color nil t))
                        bg-color "transparent")))
         (svg (svg-create svg-width svg-height
                          :viewBox svg-viewbox
                          :stroke-width 0
                          :fill fg-color)))
    (svg-rectangle svg view-x view-y view-width view-height
                   :fill bg-color)

    (dolist (item (xml-get-children (car root) 'path))
      (let* ((attrs (xml-node-attributes item))
             (path (cdr (assoc 'd attrs)))
             (fill (or (cdr (assoc 'fill attrs)) fg-color)))
        (svg-node svg 'path :d path :fill fill)))
    (svg-image svg :ascent 'center :scale 1)))

(provide 'svg-icon)
;;; svg-icon.el ends here

