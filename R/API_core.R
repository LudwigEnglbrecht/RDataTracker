# Copyright (C) President and Fellows of Harvard College and 
# Trustees of Mount Holyoke College, 2014, 2015, 2016, 2017, 2018.

# This program is free software: you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program.  If not, see
#   <http://www.gnu.org/licenses/>.

############################ API.R #############################

# This file contains files that are exported:

# prov.init - intializes a new provenance graph
# prov.save - saves the current provenance graph
# prov.quit - saves the current provenance graph and finalizes it
# prov.run - initiates execution of a script
# prov.json - returns the current provenance graph as a prov-json string


#' .ddg.init intializes a new provenance graph.
#' @param r.script.path the full path to the R script file
#' that is being executed. If provided, a copy of the script will
#' be saved with the provenance graph.
#' @param prov.dir the directory where the provenance graph will be 
#' saved. If not provided, the directory specified by the prov.dir 
#' option is used. Otherwise the R session temporary directory
#' is used.
#' @param overwrite if FALSE, includes a time stamp in the provenance
#' graph directory name.
#' @param max.snapshot.size the maximum size for snapshot files. 
#' If 0, no snapshot files are saved.
#' If -1, the complete state of an object is stored in the snapshot
#' file. For other values, the head of the object, truncated to a size near
#' the specified limit, is saved.  The size is in kilobytes. 
#' @return .ddg.init initializes the provenance collector.  The .ddg.init
#' function does not return a value.

.ddg.init <- function(r.script.path = NULL, prov.dir = NULL, overwrite = TRUE, 
  max.snapshot.size = 0) {
  
  # Initialize tables
  .ddg.init.tables()

  # Set path for provenance graph
  .ddg.set.path (prov.dir, r.script.path, overwrite)
  
  # Remove files from DDG directory
  .ddg.flush.ddg()

  # Create DDG directories
  .ddg.init.environ()

  # Reset r.script.path if RMarkdown file
  if (!is.null(r.script.path) && tools::file_ext(r.script.path) == "Rmd") {
    output.path <- paste(.ddg.path.scripts(), "/", 
                         basename(tools::file_path_sans_ext(r.script.path)), ".R", 
                         sep = "")
    .ddg.markdown(r.script.path, output.path)
    .ddg.set("ddg.r.script.path", output.path)
  } 
  
  else if (!is.null (r.script.path)) {
    .ddg.set("ddg.r.script.path",
             if (is.null(r.script.path)) NULL
             else normalizePath(r.script.path, winslash = "/"))
  }
  
  else {
    # If running from the console, set up a callback to be notified
    # after each statement completes execution and build the 
    # corresponding portions of the ddg.
    .ddg.trace.task <- function (task, result, success, printed) {
       
       # Create the provenance for the new command
       .ddg.parse.commands(as.expression(task),
             environ = .GlobalEnv,
             run.commands = FALSE)
         
       return(TRUE)
         
    }
    .ddg.set (".ddg.taskCallBack.id", addTaskCallback(.ddg.trace.task))
  }

  # Store time when script begins execution.
  .ddg.set("ddg.start.time", .ddg.timestamp())
  
  # Initialize the I/O tracing code
  .ddg.init.iotrace ()
  
  # Mark graph as initilized.
  .ddg.set(".ddg.initialized", TRUE)
  
  # Add a Console start node if running from the console.
  if (is.null (r.script.path)) {
    .ddg.add.start.node (node.name = "Console")
  }
  
  .ddg.set(".ddg.func.depth", 0)
  .ddg.set(".ddg.cur.cmd.stack", vector())
  
  invisible()
}

#' .ddg.set.path sets the path where the DDG will be stored.  It creates the 
#' directory if it does not currently exist.
#' The base directory is set as follows:
#' (1) the directory specified by the user in the parameter prov.dir, or
#' (2) the directory specified by the user as the value of the option "prov.dir", or
#' (3) the R session temporary directory. If the directory specified by the user
#' is a period (.), the base directory is set to the current working directory.
#' The provenance graph is stored in a subdirectory of the base directory called 
#' "prov_console" in console mode or "prov_[script name]" in script mode. If overwrite = 
#' FALSE, a timestamp is added to the directory name.
#' @param prov.dir name of directory.  This can be a directory name, ".", or NULL.
#' @param r.script.path the path to the R script.  If NULL, we are running from the console.
#' @param overwrite If FALSE, a timestamp is added to the directory name
#' @return the name of the directory where the ddg should be stored

.ddg.set.path <- function (prov.dir, r.script.path, overwrite) {
  
  # Directory specified by prov.dir parameter
  if (!is.null(prov.dir)) {
    if (prov.dir == ".") {
      base.dir <- getwd()
    } else {
      base.dir <- prov.dir
    }
  } 
  
  else {
    # Directory specified as an option for prov.dir
    prov.dir.option <- getOption("prov.dir")
    if (!is.null(prov.dir.option) && prov.dir.option != "") {
      if (prov.dir.option == ".") {
        base.dir <- getwd()
      } else {
        base.dir <- getOption("prov.dir")
      }
    } 
    
    # R session temporary directory
    else {
      # Normalize path
      base.dir <- normalizePath(tempdir(), winslash = "/", mustWork = FALSE)
    }
  }
  
  # Remove final slash if present
  base.dir <- sub("/$", "", base.dir)
  
  # Console mode
  if (is.null(r.script.path)) {
    ddg.path <- paste(base.dir, "/prov_console", sep="")
    
    # Script mode
  } else {
    ddg.path <- paste(base.dir, "/prov_", 
                      basename(tools::file_path_sans_ext(r.script.path)), sep="")
  }
  
  # Add timestamp if overwrite = FALSE
  if (!overwrite) ddg.path <- paste(ddg.path, "_", .ddg.timestamp(), sep="")
  
  # Create directory if it does not exist
  if (!dir.exists(ddg.path)) dir.create(ddg.path, recursive = TRUE)
  
  .ddg.set("ddg.path", ddg.path)
}

#' .ddg.flush.ddg removes all files from the DDG directories unless the
#'   the DDG directory is the working directory. If no DDG directory is
#'   specified, the current DDG directory is assumed.
#' @param ddg.path path to DDG directory.
#' @return nothing

.ddg.flush.ddg <- function(ddg.path=NULL) {
  # TODO:  When ddg.flush.ddg is removed (from Obsolete.R, we
  # can remove the ddg.path parameter and update the 
  # code below to always look up the path.
  
  # Use current DDG directories if no directory is specified.
  if (is.null(ddg.path)) {
    ddg.path <- .ddg.path()
    ddg.path.data <- .ddg.path.data()
    ddg.path.debug <- .ddg.path.debug()
    ddg.path.scripts <- .ddg.path.scripts()
  }
  
  # Remove files unless the DDG directory is the working directory.
  if (ddg.path != getwd()) {
    unlink(paste(ddg.path, "*.*", sep="/"))
    unlink(paste(ddg.path.data, "*.*", sep="/"))
    unlink(paste(ddg.path.data, ".ddghistory", sep="/"))
    unlink(paste(ddg.path.debug, "*.*", sep="/"))
    unlink(paste(ddg.path.scripts, "*.*", sep="/"))
  }
  
  invisible()
}

#' .ddg.save saves the current provenance graph to a prov-json file.
#' If more R statements are executed, the provenance for these statements
#' is added to the graph.
#' @param save.debug If TRUE, debug files are saved to the debug directory.
#'   This is intended for developers of the RDataTracker package.
#' @return .ddg.save writes the current provenance to a file but does not 
#'   return a value.

.ddg.save <- function(save.debug = FALSE) {
  if (!.ddg.is.init()) return(invisible())
  
  # If running from the console create a Console finish node.
  # Also create a start node for the next segment.
  if (is.null (.ddg.get ("ddg.r.script.path"))) {
    .ddg.add.finish.node ()
    .ddg.add.start.node (node.name = "Console")
  }

  # Save prov.json to file.
  .ddg.json.write()
  if (interactive()) print(paste("Saving prov.json in ", .ddg.path(), sep=""))
  
  # Save debug files to debug directory.
  if (save.debug || .ddg.save.debug()) {
    .ddg.save.debug.files()
  }

  invisible()
}

#' .ddg.quit saves and closes the current provenance graph.
#' @param save.debug If TRUE, debug files are saved to the debug directory.
#'   This is intended for developers of the RDataTracker package.
#' @return .ddg.quit writes the current provenance to a file but does not 
#'   return a value.

.ddg.quit <- function(save.debug = FALSE) {
  if (!.ddg.is.init()) return(invisible())
  
  # If running from the console create a Console finish node.
  if (is.null (.ddg.get ("ddg.r.script.path"))) {
    .ddg.add.finish.node ()
  }
  
  # If there are any connections still open when the script ends,
  # create nodes and edges for them.
  .ddg.create.file.nodes.for.open.connections ()
  
  # If there is a display device open, grab what is on the display
  if (length(grDevices::dev.list()) >= 1) {
    tryCatch (.ddg.capture.graphics(called.from.save = TRUE),
        error = function (e) print(e))
  }
  
  # Turn off the I/O tracing and console tracing.
  .ddg.stop.iotracing()
  if (.ddg.is.set (".ddg.taskCallBack.id")) {
    removeTaskCallback (.ddg.get (".ddg.taskCallBack.id"))
  }
  
  # Delete temporary files.
  .ddg.delete.temp()
  
  # Shut down the DDG.
  #.ddg.clear()
  # Mark graph as initilized.
  .ddg.set(".ddg.initialized", FALSE)
    
  # Save prov.json to file.
  .ddg.json.write()
  if (interactive()) print(paste("Saving prov.json in ", .ddg.path(), sep=""))
  
  # Save debug files to debug directory.
  if (save.debug || .ddg.save.debug()) {
    .ddg.save.debug.files()
  }
   
  invisible()
}

#' .ddg.run initiates execution of a script and collects provenance as 
#' the script executes.
#' @param r.script.path the full path to the R script file
#' that is being executed. If provided, a copy of the script will
#' be saved with the provenance graph.
#' @param prov.dir the directory where the provenance graph will be 
#' saved. If not provided, the directory specified by the prov.dir 
#' option is used. Otherwise the R session temporary directory
#' is used.
#' @param overwrite if FALSE, includes a time stamp in the provenance
#'   graph directory name.
#' @param f a function to run. If supplied, the function f is executed 
#' with calls to prov.init and prov.save so that provenance for the 
#' function is captured.  Exactly one of f and r.script.path should be provided.
#' @param annotate.inside.functions if TRUE, provenance is collected 
#' inside functions.
#' @param first.loop the first loop to collect provenance in a for, 
#' while, or repeat statement.
#' @param max.loops the maximum number of loops to collect
#' provenance in a for, while, or repeat statement. If max.loops = -1,
#' there is no limit. If max.loops = 0, no loops are annotated. 
#' If non-zero, it indicates the number of iterations of each loop for
#' which provenance should be collected.  If max.loops is non-zero, provenance
#' is also collected inside if-statements.
#' @param max.snapshot.size the maximum size for snapshot files. 
#' If 0, no snapshot files are saved. If -1, the complete state of an object
#' is stored in the snapshot file. For other values, the head of the object, 
#' truncated to a size near the specified limit, is saved.  The size is 
#' in kilobytes. 
#' @param save.debug If TRUE, debug files are saved to the debug directory.
#' This is intended for developers of the RDataTracker package.
#' @param display if TRUE, the provenance graph is displayed in DDG Explorer
#' @param hash.algorithm the hash algorithm to use for files.
#' Choices are md5 (default), sha1, crc32, sha256, sha512, xxhash32, 
#' xxhash64 and murmur32. This feature uses the digest function from 
#' the digest package.
#' @return .ddg.run runs a script, collecting provenance as it does so.  
#' It does not return a value. 

.ddg.run <- function(r.script.path = NULL, prov.dir = NULL, overwrite = TRUE, 
                    f = NULL, annotate.inside.functions = FALSE, first.loop = 1, 
                    max.loops = 0, max.snapshot.size = 0, save.debug = FALSE, 
                    display = FALSE, hash.algorithm="md5") {
  
  # Set .ddg.is.sourced to TRUE if script provided.
  .ddg.set(".ddg.is.sourced", !is.null(r.script.path))

  # Save debug files to debug directory.
  .ddg.set("ddg.save.debug", save.debug)

  # If an R error is generated, get the error message and close
  # the DDG.
  tryCatch(
    if (!is.null(r.script.path)) {
      .ddg.source(
         .ddg.get("ddg.r.script.path"),
          ignore.ddg.calls = FALSE)
    }
    else if (!is.null(f)) f()
    else stop("r.script.path and f cannot both be NULL"),

    finally={
      # Add finish nodes for anything left open due to errors
      .ddg.close.blocks()
      .ddg.quit(save.debug)
    }
  )
  
  invisible()
}

#' .ddg.source reads and executes an R script in the specified
#' environment. .ddg.source mimics the behaviour of the R source command, 
#' with similar input parameters and results, but with the additional 
#' parameter ignore.ddg.calls.
#' @param file the name of the R script file to source.
#' @param local the environment in which to evaluate parsed
#' expressions. If TRUE, the environment from which .ddg.source is
#' called. If FALSE, the user's workspace (global environment).
#' @param echo print each expression after parsing
#' @param print.eval print the result of each evaluation
#' @param verbose print extra diagnostics
#' @param max.deparse.length the maximum number of characters in output
#' for deparse of a single expression
#' @param chdir change the R working directory temporarily to
#' the directory containing the file to be sourced
#' @param encoding encoding to be assumed when file is a
#' character string
#' @param ignore.ddg.calls if TRUE, ignore DDG function calls
#' @param calling.script the number of the calling script
#' @param startLine the line that the source call starts on
#' @param startCol the column that the source call starts on
#' @param endLine the line that the source call ends on
#' @param endCol the column that the source call ends on
#' @return nothing

.ddg.source <- function (file,  local = FALSE, echo = verbose, print.eval = echo,
  verbose = getOption("verbose"), max.deparse.length = 150, chdir = FALSE, 
  encoding = getOption("encoding"), ignore.ddg.calls = TRUE, calling.script=NA, 
  startLine=NA, startCol=NA, endLine=NA, endCol=NA){

  # Store script number & name.
  sname <- basename(file)
  snum <- .ddg.store.script.info (sname)
  
  # Save a copy of the script
  file.copy(file, paste(.ddg.path.scripts(), basename(sname), sep="/"))

  ### CODE IN THIS SECTION IS A SLIGHT MODIFICATION OF A PORTION OF ###
  ### R's source FUNCTION ###
  
  # To see the current version of the source function source code, say:
  # getMethod("source", "ANY")
  # I don't know how to see the functions called from source, though.
  # An older version of the source code of R's source function can be found here:
  # https://github.com/SurajGupta/r-source/blob/master/src/library/base/R/source.R
  # Note that R's source function has more parameters than we allow.  This could
  # conceivably cause problems when we replace calls to source with calls to .ddg.source.
  # The additional parameters are:
  # exprs
  # spaced
  # prompt.echo
  # width.cutoff
  # deparseCtrl
  # continue.echo
  # skip.echo
  # keep.source


  # Get the environment under which the script should be executed.
  envir <- 
    if (isTRUE(local)) {
      parent.frame()
    }
    else if (isFALSE(local)) {
      .GlobalEnv
    }
    else if (is.environment(local)) {
      local
    }
    else stop("'local' must be TRUE, FALSE or an environment")

  # Parse encoding information.
  have_encoding <- !missing(encoding) && encoding != "unknown"
  if (!missing(echo)) 
  {
    if (!is.logical(echo))
      stop ("'echo' must be logical")
    if (!echo && verbose) 
    {
      warning("'verbose' is TRUE, 'echo' not; ... coercing 'echo <- TRUE'\n")
      echo <- TRUE
    }
  }

  # Print extra information about environment.
  if (verbose) 
  {
    cat("'envir' chosen:")
    print(envir)
  }

  # Parse input file and figure out encoding.
  ofile <- file
  from_file <- FALSE
  srcfile <- NULL
  if (is.character(file)) 
  {
    if (identical(encoding, "unknown")) 
    {
      enc <- utils::localeToCharset()
      encoding <- enc[length(enc)]
    }
    else enc <- encoding
    if (length(enc) > 1L) 
    {
      encoding <- NA
      owarn <- options(warn = 2)
      for (e in enc) 
      {
        if (is.na(e))
          next
        zz <- file(file, encoding = e)
        res <- tryCatch(readLines(zz, warn = FALSE), error = identity)
        close(zz)
        if (!inherits(res, "error")) 
        {
          encoding <- e
          break
        }
      }
      options(owarn)
    }
    if (is.na(encoding))
      stop("unable to find a plausible encoding")
    if (verbose)
      cat(gettextf("encoding = \"%s\" chosen", encoding), "\n", sep = "")
    if (file == "") 
    {
      filename <- "stdin"
      file <- stdin()
      srcfile <- "<stdin>"
    }
    else 
    {
      filename <- file
      file <- file(filename, "r", encoding = encoding)
      on.exit(close(file))
      lines <- readLines(file, warn = FALSE)

      on.exit()
      close(file)
      srcfile <- srcfilecopy(filename, lines, file.mtime(filename)[1], isFile = TRUE)
    }
    loc <- utils::localeToCharset()[1L]
    encoding <- if (have_encoding)
        switch(loc, `UTF-8` = "UTF-8", `ISO8859-1` = "latin1", "unknown")
          else "unknown"
  }

  else 
  {
    filename <- "Connection"
    lines <- readLines(file, warn = FALSE)

    srcfile <- srcfilecopy(deparse(substitute(file)), lines)
  }

  # Parse the expressions from the file.
  exprs <- if (!from_file) 
    {
      if (length(lines)) 
        parse(stdin(), n = -1, lines, "?", srcfile, encoding, keep.source=TRUE)
      else expression()
    }
    else {
      parse(file, n = -1, NULL, "?", srcfile, encoding, keep.source=TRUE)
    }

  on.exit()

  # Set the working directory for the current script and
  # expressions.
  if (from_file)
    close(file)

  if (verbose)
    cat("--> parsed", "expressions; now eval(.)ing them:\n")
  if (chdir) 
  {
    if (is.character (ofile)) 
    {
      if (grepl("^(ftp|http|file)://", ofile))
        warning("'chdir = TRUE' makes no sense for a URL")
      else if ( (path <- dirname (ofile)) != ".") 
      {
        owd <- getwd()
        if (is.null(owd)) 
        {
          stop("cannot 'chdir' as current directory is unknown")
          on.exit(setwd(owd), add = TRUE)
          setwd(path)
        }
      }
    }
    else {
      warning("'chdir = TRUE' makes no sense for a connection")
    }
  }

  ### END OF MODIFIED source CODE SECTION ###

  # Calculate the regular expressions for what should be ignored
  # and what shouldn't.
  # Ignore calculation of certain execution steps.
  ignores <- c("^library[(]RDataTracker[)]$",
    if (ignore.ddg.calls) "^ddg."
    else c("^prov.init", "^prov.run"))

  # Now we can parse the commands as we normally would for a DDG.
  if (length(exprs) > 0) 
  {

    # Initialize the tables for ddg.capture.
    .ddg.set("from.source", TRUE)

    # Parse and execute the commands, collecting provenance along the way.
    # If called from prov.run, there is no position information.  Otherwise,
    # record script number and posiiton in the start and finish nodes.
    if (is.na(calling.script)) {
      .ddg.add.start.node (node.name=sname)
    }
    else {
      .ddg.add.start.node (node.name=paste0 ("source (\"", sname, "\")"), 
                           script.num=calling.script,
                           startLine=startLine, startCol=startCol, 
                           endLine=endLine, endCol=endCol)
    }
    .ddg.parse.commands(exprs, sname, snum, environ=envir, ignore.patterns=ignores,
      echo = echo, print.eval = print.eval, max.deparse.length = max.deparse.length,
      run.commands = TRUE)
    if (is.na(calling.script)) {
      .ddg.add.finish.node ()
    }
    else {
      .ddg.add.finish.node (script.num=calling.script,
          startLine=startLine, startCol=startCol, endLine=endLine, endCol=endCol)
    }

  }

  invisible()
}