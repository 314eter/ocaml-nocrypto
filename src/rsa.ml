

let of_cstruct cs =
  let open Cstruct in
  let open Cstruct.BE in

  let rec loop acc = function
    | (_, 0) -> acc
      (* XXX larger words *)
    | (i, n) ->
        let x = Z.of_int @@ get_uint8 cs i in
        loop Z.((acc lsl 8) lor x) (succ i, pred n) in
  loop Z.zero (0, len cs)


let m1 = 0xffL
and m2 = 0xffffL
and m4 = 0xffffffffL
and m7 = 0xffffffffffffffL

let m1' = Z.of_int64 m1
let m2' = Z.of_int64 m2
let m4' = Z.of_int64 m4
let m7' = Z.of_int64 m7

let size_u z =

  let rec loop acc = function
    | z when z > m7' -> loop (acc + 7) Z.(shift_right z 56)
    | z when z > m4' -> loop (acc + 4) Z.(shift_right z 32)
    | z when z > m2' -> loop (acc + 2) Z.(shift_right z 16)
    | z when z > m1' -> loop (acc + 1) Z.(shift_right z 8 )
    | z              -> acc + 1 in
  loop 0 z

let to_cstruct z =
  let open Cstruct in
  let open Cstruct.BE in

  let byte = Z.of_int 0xff in
  let size = size_u z in
  let cs   = Cstruct.create size in

  let rec loop z = function
    | i when i < 0 -> ()
    | i ->
        set_uint8 cs i Z.(to_int @@ z land byte);
        loop Z.(shift_right z 8) (pred i) in

  ( loop z (size - 1) ; cs )


(* XXX proper rng *)
let random_z bytes =
  let rec loop acc = function
    | 0 -> acc
    | n ->
        let i = Random.int 0x100 in
        loop Z.((shift_left acc 8) lor of_int i) (pred n) in
  loop Z.zero order

(* XXX
 * This is fishy. Most significant bit is always set to avoid reducing the
 * modulus, but this drops 1 bit of randomness. Investigate.
 *)
let rec gen_prime_z ?mix order =
  let lead = match mix with
    | Some x -> x
    | None   -> Z.(pow (of_int 2)) (order * 8 - 1) in
  let z = Z.(random_z order lor lead) in
  match Z.probab_prime z 25 with
  | 0 -> gen_prime_z ~mix:lead order
  | _ -> z

type pub  = { e : Z.t ; n : Z.t }
type priv = {
  e  : Z.t ; d  : Z.t ; n : Z.t ;
  p  : Z.t ; q  : Z.t ;
  dp : Z.t ; dq : Z.t ; q' : Z.t
}

let pub  ~e ~n = { e ; n }

let priv ~e ~d ~n ~p ~q ~dp ~dq ~q' = { e; d; n; p; q; dp; dq; q' }

let pub_of_priv (k : priv) = { e = k.e ; n = k.n }

let priv_of_primes ~e ~p ~q =
  let n  = Z.(p * q)
  and d  = Z.(invert e (pred p * pred q)) in
  let dp = Z.(d mod (pred p))
  and dq = Z.(d mod (pred q))
  and q' = Z.(invert q p) in
  priv ~e ~d ~n ~p ~q ~dp ~dq ~q'


let print_key { e; d; n; p; q; dp; dq; q' } =
  let f = Z.to_string in
  Printf.printf
    "RSA key
  e : %s
  d : %s
  n : %s
  p : %s
  q : %s
  dp: %s
  dq: %s
  q': %s\n%!"
    (f e) (f d) (f n) (f p) (f q) (f dp) (f dq) (f q')

let generate ~e bytes =

  let (p, q) =
    let rec attempt order =
      let (p, q) = (gen_prime_z order, gen_prime_z order) in
      let phi    = Z.(pred p * pred q) in
      match p = q with
      | false when Z.(gcd e phi = one) -> (p, q)
      | _                              -> attempt order in
    attempt (bytes / 2)
  in
  priv_of_primes ~e ~p ~q


let encrypt_unsafe ~key: ({ e; n } : pub) msg = Z.(powm msg e n)

(* XXX
 * Yes, timing. Get a rnd and use blinding.
 *)
let decrypt_unsafe ~key: ({ p; q; dp; dq; q' } : priv) c =
  let m1 = Z.(powm c dp p)
  and m2 = Z.(powm c dq q) in
  let h  =
    let rec add_p = function
      | diff when diff > Z.zero -> diff
      | diff                    -> add_p Z.(p + diff) in
    Z.((q' * (add_p (m1 - m2))) mod p) in
  Z.(m2 + h * q)

let (encrypt_z, decrypt_z) =
  let aux op f ~key x =
    if x >= f key then
      invalid_arg "RSA key too small"
    else op ~key x in
  (aux encrypt_unsafe (fun k -> k.n)),
  (aux decrypt_unsafe (fun k -> k.n))

let encrypt ~key cs = to_cstruct (encrypt_z ~key (of_cstruct cs))
let decrypt ~key cs = to_cstruct (decrypt_z ~key (of_cstruct cs))


(* let attempt =
  let e = Z.of_int 43
  and m = Cstruct.of_string "AB" in
  fun () ->
    Printf.printf "+ generating...\n%!";
    let key = generate ~e 2 in
    print_key key;
    Printf.printf "+ encrypt...\n%!";
    let c = encrypt ~key:(pub_of_priv key) m in
    Printf.printf "+ decrypt...\n%!";
    let m'  = decrypt ~key c in
    assert (m = m') *)

