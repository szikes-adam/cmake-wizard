;;; cmake-wizard.el --- TODO

;;; Commentary:

;; General requirements:
;; - More build config shall be added easily (eg: -DFLAVOR=release [compiler config file])
;; - The build config shall be changeable by using its name
;; - The pre-build and post-build tasks shall be added (how to set variables? etc., post-build like running unit test)
;; - The build config shall be stored within the project as eg: .cmake-wizard-config
;; - The building shall be done by the compile function (the cmake-wizard shall give a list of targets)
;; - The gtest shall be supported (is it really needed?)
;; - The lsp-mode shall be supported
;; - The helm shall be supported
;; - The ivy shall be supported
;; - The rtags shall be supported

;;; Code:

;;; Interface:

(defgroup cmake-wizard nil
  "Use cmake and build targets easily."
  :group 'tools
  :link '(url-link :tag "GitHub" "https://github.com/szikes-adam/cmake-wizard"))

(defcustom cmake-wizard-cmake-global-arugments nil
  "Commonly used cmake arguments in all projects."
  :group 'cmake-wizard
  :type 'string)

(defcustom cmake-wizard-cmake-build-directory-path "/tmp/"
  "Specify the directory where the 'cmake-wizard-cmake-build-directory-name' is.
The nil means it is in the project root."
  :group 'cmake-wizard
  :type 'directory)

(defcustom cmake-wizard-cmake-build-directory-name "cmake-build/"
  "Specify name of directory where the generated files are.
Slash is required at the end."
  :group 'cmake-wiazrd
  :type 'string)

(defcustom cmake-wizard-cmake-executable-path nil
  "The path of cmake executable.
The nil means $PATH."
  :group 'cmake-wizard
  :type '(file :must-match t))

(defcustom cmake-wizard-cmake-wizard-setup-filename ".cmake-wizard"
  "The filename of the cmake wizard setup file.
This file is located in the specific project root.
The setup means a specific combination of compiler, architecture, flavor, etc."
  :group 'cmake-wizard
  :type 'filename)

(defun cmake-wizard-print-cmake-version ()
  "Print cmake executable version."
  (interactive)
  (cmake-wizard--print-cmake-version))

(defun cmake-wizard-show-setup ()
  "Print all setup of the specific project."
  )

(defun cmake-wizard-add-setup ()
  "Add a setup for the current project."
  (interactive)
  (cmake-wizard--add-setup))

(defun cmake-wizard-remove-setup ()
  "Remove a setup from the specific project."
  )

(defun cmake-wizard-generate-build-projectsystem ()
  "Generate the Build Projectsystem."
  (interactive)
  (cmake-wizard--generate-project-buildsystem))

(defun cmake-wizard-build-all-target ()
  "Build all targets with cmake."
  (interactive)
  (cmake-wizard--build-target "all"))

(defun cmake-wizard-temp ()
  "Asd."
  (interactive)
  (cmake-wizard--get-build-targets))

;; (defun cmake-wizard-add-build-config ()
;;   "Add new build config to the project."
;;   (interactive))

;; (defun cmake-wizard-remove-build-config ()
;;   "Remove the existing build config from the project."
;;   (interactive))

;;; Core:

(require 'projectile)

(cl-defstruct cmake-wizard--session-type
  project-path
  project-name
  build-targets
  setups)

(defconst cmake-wizard--cmake-executable-name "cmake")

(defconst cmake-wizard--process-name "cmake")

(defconst cmake-wizard--buffer-name "*cmake-wizard log*")

(defconst cmake-wizard--cmake-lists-file "CMakeLists.txt")

(defvar cmake-wizard--execution-list nil)

(defvar cmake-wizard--session (make-cmake-wizard--session-type)
  "Contains the project specific data.
This shall be always updated!")

(defun cmake-wizard--regexp-list (regexp string)
  "Return a list of all REGEXP match in STRING."
  ;; source: http://emacs.stackexchange.com/questions/7148/get-all-regexp-matches-in-buffer-as-a-list
  (let ((pos 0)
	(matches ()))
    (while (string-match regexp string pos)
      (push (match-string 1 string) matches)
      (setq pos (match-end 0)))
    (setq matches (reverse matches))
    matches))

(defun cmake-wizard--do-with-buffer (do)
  "Switch to buffer, do the DO then switch back."
  (let ((current-buffer (current-buffer)))
    (set-buffer (cmake-wizard--get-buffer))
    (read-only-mode -1)
    (goto-char (point-max))
    (funcall do)
    (read-only-mode 1)
    (set-buffer current-buffer)))

(defun cmake-wizard--build-message (string &rest objects)
  "Build message based on STRING and OBJECTS."
  (let ((base-string (format "cmake-wizard [%s]" (current-time-string)))
	(got-string (apply 'format string objects)))
    (concat base-string " " got-string)))

(defun cmake-wizard--print-message-and-buffer (string &rest objects)
  "Print STRING and OBJECTS in *Messgae* and own buffer."
  (let ((built-string (apply 'cmake-wizard--build-message string objects)))
    (apply 'message string objects)
    (cmake-wizard--do-with-buffer (lambda () (insert built-string "\n")))))

(defun cmake-wizard--print-buffer (string &rest objects)
  "Print STRING and OBJECTS in only own buffer."
  (let ((built-string (apply 'cmake-wizard--build-message string objects)))
    (cmake-wizard--do-with-buffer (lambda () (insert built-string "\n")))))

(defun cmake-wizard--throw-error (string &rest objects)
  "Throw an error with STRING and OBJECTS."
  (apply 'cmake-wizard--print-buffer string objects)
  (apply 'error string objects))

(defun cmake-wizard--generate-buffer (buffer-name)
  "Generate buffer with BUFFER-NAME."
  (let ((current-buffer (current-buffer))
        (new-buffer (get-buffer-create buffer-name)))
    (set-buffer new-buffer)
    (read-only-mode 1)
    (set-buffer current-buffer)))

(defun cmake-wizard--get-buffer ()
  "Get buffer and generate it, if it does not exist."
  (unless (get-buffer cmake-wizard--buffer-name)
    (cmake-wizard--generate-buffer cmake-wizard--buffer-name))
  (get-buffer cmake-wizard--buffer-name))

(defun cmake-wizard--push-back-execution (exec)
  "Store in execution list the EXEC.
The EXEC shall be a callable object like lambda function."
  (push exec cmake-wizard--execution-list))

(defun cmake-wizard--perform-execution ()
  "Restore from execution list and execute it."
  (when cmake-wizard--execution-list
    (let ((exec (car (last cmake-wizard--execution-list))))
      (funcall exec)
      (setq cmake-wizard--execution-list (butlast cmake-wizard--execution-list)))))

(defun cmake-wizard--get-project-root-dir ()
  "Return with the project root directory based on the current position."
  (let ((root (projectile-project-root)))
    (unless root
      (cmake-wizard--throw-error "Project has not found based on buffer %s (%s)"
				 (buffer-name)
				 (buffer-file-name)))
    (cmake-wizard--print-buffer "Project has found with name %s (%s)"
				(cmake-wizard--get-project-name)
				root)
    root))

(defun cmake-wizard--test-whether-cmake-project ()
  "Test wheter the current prject is cmake project."
  (let ((path (concat
	       (cmake-wizard--get-project-root-dir)
	       cmake-wizard--cmake-lists-file)))
    (unless (file-exists-p path)
      (cmake-wizard--throw-error "The project %s (%s) is not cmake project"
				 (cmake-wizard--get-project-name)
				 (cmake-wizard--get-project-root-dir)))))

(defun cmake-wizard--get-build-root-path ()
  "Return with the full path of the build root."
  (concat (or
	   cmake-wizard-cmake-build-directory-path
	   (cmake-wizard--get-project-root-dir))
	  cmake-wizard-cmake-build-directory-name))

(defun cmake-wizard--get-build-project-path ()
  "Return with the full path of the project specific build directory."
  (let* ((project-path (cmake-wizard--get-project-root-dir))
	 (directory (replace-regexp-in-string "/" "_" project-path))
	 (root-path (cmake-wizard--get-build-root-path))
	 (build-path (concat root-path directory)))
    (unless (file-directory-p build-path)
      (make-directory build-path root-path))
    build-path))

(defun cmake-wizard--get-project-name ()
  "Return with the project name based on the current position."
  (projectile-project-name))

(defun cmake-wizard--register-callback (process-name callback)
  "Register CALLBACK on process of PROCESS-NAME."
  (set-process-sentinel (get-process process-name) callback))

(defun cmake-wizard--run-program (process-name program &rest program-args)
  "Run PROGRAM with PROCESS-NAME and PROGRAM-ARGS."
  (when (get-process process-name)
    (cmake-wizard--throw-error "Another process of %s is running with name: %s (ID: %d)"
			       program
			       (get-process process-name)
			       (process-id (get-process process-name))))
  (cmake-wizard--print-buffer (concat
			       "Run: "
			       program
			       " "
			       (mapconcat 'identity program-args " ")))
  (apply
   'start-process
   process-name
   (cmake-wizard--get-buffer)
   program
   program-args))

(defun cmake-wizard--get-cmake-executable ()
  "Return with cmake executable."
  (or cmake-wizard-cmake-executable-path cmake-wizard--cmake-executable-name))

(defun cmake-wizard--run-cmake (callback &rest program-args)
  "Run cmake with PROGRAM-ARGS then register CALLBACK."
  (apply 'cmake-wizard--run-program
	 cmake-wizard--process-name
	 (cmake-wizard--get-cmake-executable)
	 program-args)
  (cmake-wizard--register-callback cmake-wizard--process-name callback))

(defun cmake-wizard--send-output-to-buffer (proc string)
  "The output STRING of PROC is printed on the buffer of PROC."
  (when (buffer-live-p (process-buffer proc))
    (with-current-buffer (process-buffer proc)
      (let ((moving (= (point) (process-mark proc))))
	(save-excursion
	  (goto-char (process-mark proc))
	  (cmake-wizard--do-with-buffer (lambda () (insert string)))
	  (set-marker (process-mark proc) (point)))
	(when moving
	  (goto-char (process-mark proc)))))))

(defun cmake-wizard--request-build-targets-if-needs (string)
  "Request to get build targets based on the output (STRING) of cmake."
  (when (string-match "Generating done" string)
    (cmake-wizard--push-back-execution (lambda () (cmake-wizard--get-build-targets)))))

(defun cmake-wizard--filter-cmake-version (proc string)
  "Print cmake version of PROC based on STRING."
  (string-match "\\([0-9]+.[0-9.]+[a-zA-Z0-9\\-_.]*\\)" string)
  (let ((version (match-string 1 string)))
    (when (version)
      (cmake-wizard--print-message-and-buffer "cmake version: %s" version)))
  (cmake-wizard--send-output-to-buffer proc string))

(defun cmake-wizard--filter-generate-project-buildsystem (proc string)
  "Filter the output (STRING) of cmake (PROC)."
  (cmake-wizard--request-build-targets-if-needs string)
  (cmake-wizard--send-output-to-buffer proc string))

(defun cmake-wizard--filter-get-build-targets (proc string)
  "Store the build targets from STRING of PROC."
  ;; [!-~] means all printable character except the space
  (let ((targets (cmake-wizard--regexp-list "\\.\\.\\. \\([!-~]+\\)" string)))
    (setf (cmake-wizard--session-type-build-targets cmake-wizard--session) targets))
  (cmake-wizard--send-output-to-buffer proc string))

(defun cmake-wizard--filter-build-target (proc string)
  "Filter the output (STRING) of cmake (PROC)."
  (cmake-wizard--request-build-targets-if-needs string)
  (cmake-wizard--send-output-to-buffer proc string))

(defun cmake-wizard--print-cmake-version ()
  "Print cmake version.
cmake --version"
  (cmake-wizard--run-cmake nil "-version")
  (set-process-filter
   (get-process cmake-wizard--process-name)
   'cmake-wizard--filter-cmake-version))

(defun cmake-wizard--add-setup ()
  "Add a setup for the current project."
  ()
  (cmake-wizard--print-message-and-buffer "Setup name: %s, specs: %s" (read-string "Enter setup name:") (read-string "specs:")))

(defun cmake-wizard--generate-project-buildsystem (&rest options)
  "Run cmake on project to generate the Project Buildsystem with OPTIONS.
cmake <OPTIONS> -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -S <project path> -B <build path>"
  (cmake-wizard--test-whether-cmake-project)
  (cmake-wizard--run-cmake
   (lambda (process event)
     (let ((status (process-exit-status process)))
     (unless (= 0 status)
       (cmake-wizard--throw-error "The cmake has failed (exit code: %d), see the %s"
				  status
				  cmake-wizard--buffer-name))
     (cmake-wizard--print-message-and-buffer "Success - generate")
     (cmake-wizard--perform-execution)))
   (mapconcat 'identity options " ")
   "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
   "-S"
   (cmake-wizard--get-project-root-dir)
   "-B"
   (cmake-wizard--get-build-project-path))
  (set-process-filter
   (get-process cmake-wizard--process-name)
   'cmake-wizard--filter-generate-project-buildsystem))

(defun cmake-wizard--get-build-targets ()
  "Get and store the build targets of the current project.
cmake --build <build path> --target help"
  (cmake-wizard--test-whether-cmake-project)
  (cmake-wizard--run-cmake
   (lambda (process event)
     (let ((status (process-exit-status process)))
     (unless (= 0 status)
       (cmake-wizard--throw-error "The cmake has failed (exit code: %d), see the %s"
				  status
				  cmake-wizard--buffer-name))
     (cmake-wizard--print-message-and-buffer "Success - list targets")
     (cmake-wizard--perform-execution)))
   "--build"
   (cmake-wizard--get-build-project-path)
   "--target"
   "help")
  (set-process-filter
   (get-process cmake-wizard--process-name)
   'cmake-wizard--filter-get-build-targets))

(defun cmake-wizard--build-target (target &rest options)
  "Run cmake to build TARGET with build OPTIONS for native tool.
cmake --build <build path> --target <TARGET> -- <OPTIONS>"
  (cmake-wizard--test-whether-cmake-project)
  (apply 'cmake-wizard--run-cmake
   (lambda (process event)
     (let ((status (process-exit-status process)))
     (unless (= 0 status)
       (cmake-wizard--throw-error "The cmake has failed (exit code: %d), see the %s"
				  status
				  cmake-wizard--buffer-name))
     (cmake-wizard--print-message-and-buffer "Success")
     (cmake-wizard--perform-execution)))
   "--build"
   (cmake-wizard--get-build-project-path)
   "--target"
   target
   "--"
   options)
  (set-process-filter
   (get-process cmake-wizard--process-name)
   'cmake-wizard--filter-build-target))

(provide 'cmake-wizard)
;;; cmake-wizard.el ends here
