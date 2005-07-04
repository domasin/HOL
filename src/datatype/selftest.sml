(* tests for Hol_datatype *)

open HolKernel Parse

val _ = Feedback.set_trace "Theory.save_thm_reporting" 0;

fun Hol_datatype q = let
  open TextIO Feedback
  val _ = Datatype.Hol_datatype q
      handle e => (output(stdErr, "Exception raised: "^exn_to_string e);
                   Process.exit Process.failure)
in
  ()
end

val _ = Hol_datatype `type1 = one_constructor`
val _ = Hol_datatype `type2 = ##`;
val _ = Hol_datatype `type3 = /\`;
val _ = Hol_datatype `type4 = /\ | \/ | feh`;
val _ = Hol_datatype `type5 = foo of num | bar of 'a`;


val _ = Hol_datatype `foo = NIL | CONS of 'a => foo`;
val _ = Hol_datatype `list = NIL | :: of 'a => list`;
val _ = Hol_datatype `void = Void`;
val _ = Hol_datatype `pair = CONST of 'a#'b`;
val _ = Hol_datatype `onetest = OOOO of one`;
val _ = Hol_datatype `tri = Hi | Lo | Fl`;
val _ = Hol_datatype `iso = ISO of 'a`;
val _ = Hol_datatype `ty = C1 of 'a
          | C2
          | C3 of 'a => 'b => ty
          | C4 of ty => 'c => ty => 'a => 'b
          | C5 of ty => ty`;
val _ = Hol_datatype `bintree = LEAF of 'a | TREE of bintree => bintree`;
val _ = Hol_datatype `typ = C of one => (one#one)
                      => (one -> one -> 'a list)
                      => ('a,one#one,'a list) ty`;
val _ = Hol_datatype `Typ = D of one # (one#one)
                      # (one -> one -> 'a list)
                      # ('a, one#one, 'a list) ty`;

val _ = Hol_datatype `
       var = V of num ;

     atexp = var_exp of var
           | let_exp of dec => exp ;

       exp = aexp    of atexp
           | app_exp of exp => atexp
           | fn_exp  of match ;

     match = match  of rule
           | matchl of rule => match ;

      rule = rule of pat => exp ;

       dec = val_dec   of valbind
           | local_dec of dec => dec
           | seq_dec   of dec => dec ;

   valbind = bind  of pat => exp
           | bindl of pat => exp => valbind
           | rec_bind of valbind ;

       pat = wild_pat
           | var_pat of var`;

val state = Type`:ind->bool`;
val nexp  = Type`:^state -> ind`;
val bexp  = Type`:^state -> bool`;

val _ = Hol_datatype `comm = skip
            | :=    of bool list => ^nexp
            | ;;    of comm => comm
            | if    of ^bexp => comm => comm
            | while of ^bexp => comm`;

val _ = Hol_datatype
          `ascii = ASCII of bool=>bool=>bool=>bool=>bool=>bool=>bool=>bool`;


val _ = Process.exit Process.success;
