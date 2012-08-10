(*---------------------------------------------------------------------------
                An ML script for building HOL
 ---------------------------------------------------------------------------*)

structure build =
struct

structure Process = OS.Process

open buildutils

(* utilities *)

(* ----------------------------------------------------------------------
    Magic to ensure that interruptions (SIGINTs) are actually seen by the
    linked executable as Interrupt exceptions
   ---------------------------------------------------------------------- *)

prim_val catch_interrupt : bool -> unit = 1 "sys_catch_break";
val _ = catch_interrupt true;

(* values from the Systeml structure, which is created at HOL configuration
   time *)
val OS = Systeml.OS;
val HOLDIR = Systeml.HOLDIR
val EXECUTABLE = Systeml.xable_string (fullPath [HOLDIR, "bin", "build"])
val DEPDIR = Systeml.DEPDIR
val GNUMAKE = Systeml.GNUMAKE
val DYNLIB = Systeml.DYNLIB

(* ----------------------------------------------------------------------
    Analysing the command-line
   ---------------------------------------------------------------------- *)

val dfltbuildseq = fullPath [HOLDIR, "tools", "build-sequence"]

val {kernelspec,seqname = bseq_fname,rest = cmdline} =
    case get_cline {default_seq = dfltbuildseq} of
      Normal x => x
    | Clean s => {kernelspec = "", seqname = dfltbuildseq, rest = [s]}

(* do self-tests? and to what level *)
val (do_selftests, cmdline) = cline_selftest cmdline

(*---------------------------------------------------------------------------
     Source directories.
 ---------------------------------------------------------------------------*)

val kname = String.extract(kernelspec,1,NONE)

val SRCDIRS =
    if cmdline = ["help"] then []
    else read_buildsequence {kernelname = kname} bseq_fname

val SIGOBJ = fullPath [HOLDIR, "sigobj"];
val HOLMAKE = fullPath [HOLDIR, "bin/Holmake"]

open Systeml;
fun SYSTEML clist = Process.isSuccess (Systeml.systeml clist)

fun Holmake dir =
  if SYSTEML [HOLMAKE, "--qof"] then
    if do_selftests > 0 andalso
       FileSys.access("selftest.exe", [FileSys.A_EXEC])
    then
      (print "Performing self-test...\n";
       if SYSTEML [dir ^ "/selftest.exe", Int.toString do_selftests] then
         print "Self-test was successful\n"
       else
         die ("Selftest failed in directory "^dir))
    else
      ()
  else die ("Build failed in directory "^dir);


fun Gnumake dir =
  if SYSTEML [GNUMAKE] then true
  else (warn ("Build failed in directory "^dir ^" ("^GNUMAKE^" failed).");
        false)

(* ----------------------------------------------------------------------
   Some useful file-system utility functions
   ---------------------------------------------------------------------- *)

(* create a symbolic link - Unix only *)
fun link b s1 s2 =
  let open Process
  in if SYSTEML ["ln", "-s", s1, s2] then ()
     else die ("Unable to link file "^quote s1^" to file "^quote s2^".")
  end


(* uploadfn is of type : bool -> string -> string -> unit
     the boolean is whether or not the arguments are binary files
     the strings are source and destination file-names, in that order
*)
fun transfer_file uploadfn targetdir (df as (dir,file)) = let
  fun transfer binaryp (dir,file1,file2) =
    uploadfn binaryp (fullPath [dir,file1]) (fullPath [targetdir,file2])
  fun idtransfer binaryp (dir,file) =
      case Path.base file of
        "selftest" => ()
      | _ => transfer binaryp (dir,file,file)
  fun digest_sig file =
      let val b = Path.base file
      in if (String.extract(b,String.size b -4,NONE) = "-sig"
             handle _ => false)
         then SOME (String.extract(b,0,SOME (String.size b - 4)))
         else NONE
      end
  fun augmentSRCFILES file = let
    open TextIO
    val ostrm = openAppend (Path.concat(SIGOBJ,"SRCFILES"))
  in
    output(ostrm,fullPath[dir,file]^"\n") ;
    closeOut ostrm
  end

in
  case Path.ext file of
    SOME"ui"     => idtransfer true df
  | SOME"uo"     => idtransfer true df
  | SOME"so"     => idtransfer true df   (* for dynlibs *)
  | SOME"xable"  => idtransfer true df   (* for executables *)
  | SOME"sig"    => (idtransfer false df; augmentSRCFILES (Path.base file))
  | SOME"sml"    => (case digest_sig file of
                       NONE => ()
                     | SOME file' =>
                       (transfer false (dir,file, file' ^".sig");
                        augmentSRCFILES file'))
  |    _         => ()
end;


(*---------------------------------------------------------------------------
           Compile a HOL directory in place. Some libraries,
           e.g., the robdd libraries, need special treatment because
           they come with external tools or C libraries.
 ---------------------------------------------------------------------------*)

exception BuildExit
fun build_dir (dir, regulardir) = let
  val _ = if do_selftests >= regulardir then ()
          else raise BuildExit
  val _ = FileSys.chDir dir
  val truncdir = if String.isPrefix HOLDIR dir then
                   String.extract(dir, size HOLDIR + 1, NONE)
                   (* +1 to drop directory slash after holdir *)
                 else dir
  val now_d = Date.fromTimeLocal (Time.now())
  val now_s = Date.fmt "%d %b, %H:%M:%S" now_d
  val _ = print ("Building directory "^truncdir^" ["^now_s^"]\n")
in
  case #file(Path.splitDirFile dir) of
    "muddyC" => let
    in
      case OS of
        "winNT" => bincopy (fullPath [HOLDIR, "tools", "win-binaries",
                                      "muddy.so"])
                           (fullPath [HOLDIR, "examples", "muddy", "muddyC",
                                      "muddy.so"])
      | other => if not (Gnumake dir) then
                   print(String.concat
                           ["\nmuddyLib has NOT been built!! ",
                            "(continuing anyway).\n\n"])
                 else ()
    end
  | "HolCheck" => if not DYNLIB then
                    warn "*** Not building HolCheck as Dynlib, and hence \
                         \HolBddLib, not available"
                  else Holmake dir
  | "minisat" => let
    in case OS of
	   "winNT" => bincopy (fullPath [HOLDIR, "tools", "win-binaries",
					 "minisat.exe"])
                              (fullPath [HOLDIR, "src","HolSat","sat_solvers","minisat", "minisat.exe"])
	 | other => if not (Gnumake dir) then
			print(String.concat
				  ["\nMiniSat has NOT been built!! ",
				   "(continuing anyway).\n\n"])
                    else ()
    end
  | "zc2hs" => let
    in case OS of
	   "winNT" => bincopy (fullPath [HOLDIR, "tools", "win-binaries",
					 "zc2hs.exe"])
                              (fullPath [HOLDIR, "src","HolSat","sat_solvers","zc2hs", "zc2hs.exe"])
	 | other => if not (Gnumake dir) then
			print(String.concat
				  ["\nzc2hs has NOT been built!! ",
				   "(continuing anyway).\n\n"])
                    else ()
    end
  | _ => Holmake dir
end
handle OS.SysErr(s, erropt) =>
       die ("OS error: "^s^" - "^
            (case erropt of SOME s' => OS.errorMsg s' | _ => ""))
     | BuildExit => ()


(*---------------------------------------------------------------------------
        Transport a compiled directory to another location. The
        symlink argument says whether this is via a symbolic link,
        or by copying. The ".uo", ".ui", ".so", ".xable" and ".sig"
        files are transported.
 ---------------------------------------------------------------------------*)

fun upload ((src, regulardir), target, symlink) =
    if regulardir = 0 then
      (print ("Uploading files to "^target^"\n");
       map_dir (transfer_file symlink target) src)
      handle OS.SysErr(s, erropt) =>
             die ("OS error: "^s^" - "^
                  (case erropt of SOME s' => OS.errorMsg s'
                                | _ => ""))
    else if do_selftests >= regulardir then
      print ("Self-test directory "^src^" built successfully.\n")
    else ()

(*---------------------------------------------------------------------------
    For each element in SRCDIRS, build it, then upload it to SIGOBJ.
    This allows us to have the build process only occur w.r.t. SIGOBJ
    (thus requiring only a single place to look for things).
 ---------------------------------------------------------------------------*)

fun buildDir symlink s = (build_dir s; upload(s,SIGOBJ,symlink));

fun build_src symlink = List.app (buildDir symlink) SRCDIRS

(*---------------------------------------------------------------------------*)
(* In clean_sigobj, we need to avoid removing the systeml stuff that will    *)
(* have been put into sigobj by the action of configure.sml                  *)
(*---------------------------------------------------------------------------*)

fun equal x y = (x=y);
fun mem x l = List.exists (equal x) l;

fun clean_sigobj() =
 let val _ = print ("Cleaning out "^SIGOBJ^"\n")
     val lowcase = String.map Char.toLower
     fun sigobj_rem_file s =
      let val f = Path.file s
          val n = lowcase (hd (String.fields (equal #".") f))
      in
         if mem n ["systeml", "cvs", "", "readme", "preprocess", "basis2002"]
          then ()
          else rem_file s
      end
     fun write_initial_srcfiles () =
      let open TextIO
          val outstr = openOut (fullPath [HOLDIR,"sigobj","SRCFILES"])
      in
        output(outstr, fullPath [HOLDIR, "tools", "Holmake", "Systeml"]);
        output(outstr, "\n");
        closeOut(outstr)
      end
 in
  map_dir (sigobj_rem_file o normPath o Path.concat) SIGOBJ;
  write_initial_srcfiles ();
  print (SIGOBJ ^ " cleaned\n")
 end;

fun build_adoc_files () = let
  val docdirs = let
    val instr = TextIO.openIn(fullPath [HOLDIR, "tools",
                                        "documentation-directories"])
    val wholefile = TextIO.inputAll instr before TextIO.closeIn instr
  in
    map normPath (String.tokens Char.isSpace wholefile)
  end handle _ => (print "Couldn't read documentation directories file\n";
                   [])
  val doc2txt = fullPath [HOLDIR, "help", "src-sml", "Doc2Txt.exe"]
  fun make_adocs dir = let
    val fulldir = fullPath [HOLDIR, dir]
  in
    if SYSTEML [doc2txt, fulldir, fulldir] then true
    else
      (print ("Generation of ASCII doc files failed in directory "^dir^"\n");
       false)
  end
in
  List.all make_adocs docdirs
end

fun build_help () =
 let val dir = Path.concat(Path.concat (HOLDIR,"help"),"src-sml")
     val _ = FileSys.chDir dir

     (* builds the documentation tools called below *)
     val _ = SYSTEML [HOLMAKE, "all"]

     val doc2html = fullPath [dir,"Doc2Html.exe"]
     val docpath  = fullPath [HOLDIR, "help", "Docfiles"]
     val htmlpath = fullPath [docpath, "HTML"]
     val _        = if (FileSys.isDir htmlpath handle _ => false) then ()
                    else (print ("Creating directory "^htmlpath^"\n");
                          FileSys.mkDir htmlpath)
     val cmd1     = [doc2html, docpath, htmlpath]
     val cmd2     = [fullPath [dir,"makebase.exe"]]
     val _ = print "Generating ASCII versions of Docfiles...\n"
     val _ = if build_adoc_files () then print "...ASCII Docfiles done\n"
             else ()
 in
   print "Generating HTML versions of Docfiles...\n"
 ;
   if SYSTEML cmd1 then print "...HTML Docfiles done\n"
   else die "Couldn't make html versions of Docfiles"
 ;
   if (print "Building Help DB\n"; SYSTEML cmd2) then ()
   else die "Couldn't make help database"
 end;

fun make_buildstamp () =
 let open Path TextIO
     val stamp_filename = concat(HOLDIR, concat("tools","build-stamp"))
     val stamp_stream = openOut stamp_filename
     val date_string = Date.toString (Date.fromTimeLocal (Time.now()))
 in
    output(stamp_stream, "built "^date_string);
    closeOut stamp_stream
end

val logdir = Systeml.build_log_dir
val logfilename = Systeml.build_log_file
val hostname = if Systeml.isUnix then
                 case Mosml.run "hostname" [] "" of
                   Mosml.Success s => String.substring(s,0,size s - 1) ^ "-"
                                      (* substring to drop \n in output *)
                 | _ => ""
               else "" (* what to do under windows? *)

fun setup_logfile () = let
  open FileSys
  fun ensure_dir () =
      if access (logdir, []) then
        isDir logdir
      else (mkDir logdir; true)
in
  if ensure_dir() then
    if access (logfilename, []) then
      warn "Build log exists; new logging will concatenate onto this file"
    else let
        (* touch the file *)
        val outs = TextIO.openOut logfilename
      in
        TextIO.closeOut outs
      end
  else warn "Couldn't make or use build-logs directory"
end handle Io _ => warn "Couldn't set up build-logs"

fun finish_logging buildok = let
in
  if FileSys.access(logfilename, []) then let
      open Date
      val timestamp = fmt "%Y-%m-%dT%H%M" (fromTimeLocal (Time.now()))
      val newname0 = hostname^timestamp
      val newname = (if buildok then "" else "bad-") ^ newname0
    in
      FileSys.rename {old = logfilename, new = fullPath [logdir, newname]}
    end
  else ()
end handle Io _ => warn "Had problems making permanent record of build log"

val () = Process.atExit (fn () => finish_logging false)
        (* this will do nothing if finish_logging happened normally first;
           otherwise the log's bad version will be recorded *)

fun build_hol symlink = let
in
  clean_sigobj();
  setup_logfile();
  build_src symlink
    handle Interrupt => (finish_logging false; die "Interrupted");
  finish_logging true;
  make_buildstamp();
  build_help();
  print "\nHol built successfully.\n"
end


(*---------------------------------------------------------------------------
       Get rid of compiled code and dependency information.
 ---------------------------------------------------------------------------*)

fun cleandir dir = ignore (buildutils.clean HOLDIR dir)
fun cleanAlldir dir = ignore (buildutils.cleanAll HOLDIR dir)

fun clean_dirs f =
    clean_sigobj() before
    (* clean both kernel directories, regardless of which was actually built,
       the help src directory too, and all the src directories, including
       those with ! annotations  *)
    buildutils.clean_dirs {HOLDIR=HOLDIR, action = f}
                          (fullPath [HOLDIR, "help", "src-sml"] ::
                           fullPath [HOLDIR, "src", "0"] ::
                           fullPath [HOLDIR, "src", "experimental-kernel"] ::
                           fullPath [HOLDIR, "src", "logging-kernel"] ::
                           map #1 SRCDIRS)

fun check_against s = let
  open Time
  val cfgtime = FileSys.modTime (fullPath [HOLDIR, s])
in
  if FileSys.modTime EXECUTABLE < cfgtime then
    (warn ("WARNING! WARNING!");
     warn ("  The build file is older than " ^ s ^ ";");
     warn ("  this suggests you should reconfigure the system.");
     warn ("  Press Ctl-C now to abort the build; <RETURN> to continue.");
     warn ("WARNING! WARNING!");
     ignore (TextIO.inputLine TextIO.stdIn))
  else ()
end handle OS.SysErr _ => die ("File "^s^" has disappeared.");

val _ = check_against "tools/smart-configure.sml"
val _ = check_against "tools/configure.sml"
val _ = check_against "tools/build.sml"
val _ = check_against "tools/Holmake/Systeml.sig"
val _ = check_against "tools/configure-mosml.sml"

fun symlink_check() =
    if OS = "winNT" then
      die "Sorry; symbolic linking isn't available under Windows NT"
    else link

val default_link = if OS = "winNT" then cp else link

val _ =
    case cmdline of
      []            => build_hol default_link
    | ["-symlink"]  => build_hol (symlink_check()) (* w/ symbolic linking *)
    | ["-small"]    => build_hol mv                (* by renaming *)
    | ["-dir",path] => buildDir cp (path, 0)
    | ["-dir",path,
       "-symlink"]  => buildDir (symlink_check()) (path, 0)
    | ["-nosymlink"]=> build_hol cp
    | ["-clean"]    => clean_dirs buildutils.clean
    | ["-cleanAll"] => clean_dirs buildutils.cleanAll
    | ["clean"]     => clean_dirs buildutils.clean
    | ["cleanAll"]  => clean_dirs buildutils.cleanAll
    | ["symlink"]   => build_hol (symlink_check())
    | ["nosymlink"] => build_hol cp
    | ["small"]     => build_hol mv
    | ["help"]      => build_help()
    | otherwise     => warn help_mesg

end (* struct *)
