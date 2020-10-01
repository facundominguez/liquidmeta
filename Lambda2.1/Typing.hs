{-# LANGUAGE GADTs #-}

{-@ LIQUID "--reflection"  @-}
{-@ LIQUID "--ple"         @-}
{-@ LIQUID "--short-names" @-}

module Typing where

import Prelude hiding (max)
import Language.Haskell.Liquid.ProofCombinators hiding (withProof)
import qualified Data.Set as S

import Basics
import Semantics
import SystemFWellFormedness
import SystemFTyping
import WellFormedness
import BasicPropsSubstitution
import BasicPropsEnvironments
import BasicPropsWellFormedness
import SystemFLemmasWellFormedness
import SystemFLemmasFTyping
import SystemFLemmasSubstitution
--import STLCSoundness

{-@ reflect foo24 @-}   
foo24 x = Just x 
foo24 :: a -> Maybe a 

-----------------------------------------------------------------------------
----- | JUDGEMENTS : the Typing Relation and the Subtyping Relation
-----------------------------------------------------------------------------

{-@ reflect selfify @-} 
{-@ selfify :: p:Pred -> b:Basic -> z:Vname -> x:Vname 
        -> { p':Pred | fv p' == Set_cup (fv p) (Set_sng x) && 
                       TRefn b z p' == self (TRefn b z p) x } @-}
selfify :: Pred -> Basic -> Vname -> Vname -> Pred
selfify p TBool   z x = App (App (Prim And) p) (App (App (Prim Eqv) (BV z)) (FV x))
selfify p TInt    z x = App (App (Prim And) p) (App (App (Prim Eq)  (BV z)) (FV x))
selfify p (FTV a) z x = App (App (Prim And) p) (App (App (AppT (Prim Eql)
                                              (TRefn (FTV a) 1 (Bc True))) (BV z)) (FV x))
selfify p (BTV a) z x = App (App (Prim And) p) (App (App (AppT (Prim Eql)
                                              (TRefn (BTV a) 1 (Bc True))) (BV z)) (FV x))

{-@ reflect self @-}
{-@ self :: t:Type -> x:Vname -> { t':Type | Set_sub (free t') (Set_cup (free t) (Set_sng x)) &&
                                             tfreeBV t' == tfreeBV t && erase t == erase t' } @-}
self :: Type -> Vname -> Type
self (TRefn b z p) x = case b of
  TBool   -> TRefn b z (App (App (Prim And) p) (App (App (Prim Eqv) (BV z)) (FV x)))
  TInt    -> TRefn b z (App (App (Prim And) p) (App (App (Prim Eq)  (BV z)) (FV x)))
  (FTV a) -> TRefn b z (App (App (Prim And) p) (App (App (AppT (Prim Eql) 
                                                  (TRefn b 1 (Bc True))) (BV z)) (FV x)))
  (BTV a) -> TRefn b z (App (App (Prim And) p) (App (App (AppT (Prim Eql)
                                                  (TRefn b 1 (Bc True))) (BV z)) (FV x)))
self (TFunc   z t_z t) x = TFunc   z t_z t
self (TExists z t_z t) x = TExists z t_z (self t x)
self (TPoly   a k_a t) x = TPoly   a k_a t

{-@ lem_tsubFV_self1 :: z:Vname -> z':Vname -> t:Type -> { x:Vname | x == z }
        -> { pf:_ | tsubFV z (FV z') (self t x) == self (tsubFV z (FV z') t) z' } @-}
lem_tsubFV_self1 :: Vname -> Vname -> Type -> Vname -> Proof
lem_tsubFV_self1 z z' (TRefn b w p)     x = case b of
  TBool   -> () 
  TInt    -> () 
  (FTV a) -> ()
  (BTV a) -> ()
lem_tsubFV_self1 z z' (TFunc   y t_y t) x = ()
lem_tsubFV_self1 z z' (TExists y t_y t) x = () ? lem_tsubFV_self1 z z' t x
lem_tsubFV_self1 z z' (TPoly   a k_a t) x = ()

{-@ lem_tsubFV_self2 :: z:Vname -> v:Value -> t:Type -> { x:Vname | x != z }
        -> { pf:_ | tsubFV z v (self t x) == self (tsubFV z v t) x } @-}
lem_tsubFV_self2 :: Vname -> Expr -> Type -> Vname -> Proof
lem_tsubFV_self2 z v (TRefn b w p) x      = case b of
  TBool   -> ()
  TInt    -> ()
  (FTV a) -> ()
  (BTV a) -> ()
lem_tsubFV_self2 z v  (TFunc   y t_y t) x = ()
lem_tsubFV_self2 z v  (TExists y t_y t) x = () ? lem_tsubFV_self2 z v t x
lem_tsubFV_self2 z v  (TPoly   a k_a t) x = ()


{-@ lem_tsubFV_value_self :: b:Basic -> z:Vname -> p:Pred -> { x:Vname | not (Set_mem x (fv p)) }
        -> v:Value -> { pf:_ | tsubFV x v (self (TRefn b z p) x) 
                                == TRefn b z (App (App (Prim And) p)
                                                  (App (App (equals b) (BV z)) v)) } @-}
lem_tsubFV_value_self :: Basic -> Vname -> Pred -> Vname -> Expr -> Proof
lem_tsubFV_value_self b z p x v 
  = undefined -- toProof ( subFV x v p === p )

{- @ equals :: b:Basic -> { c:Prim | Set_emp (fv (Prim c)) && Set_emp (freeBV (Prim c)) &&
                  erase_ty c == FTFunc (FTBasic b) (FTFunc (FTBasic b) (FTBasic TBool)) } @-}
{-@ reflect equals @-}
{-@ equals :: b:Basic -> { e:Expr | Set_emp (fv e) && Set_emp (freeBV e) } @-}
equals :: Basic -> Expr
equals TBool   = Prim Eqv
equals TInt    = Prim Eq
equals (FTV a) = AppT (Prim Eql) (TRefn (FTV a) 1 (Bc True))
equals (BTV a) = AppT (Prim Eql) (TRefn (BTV a) 1 (Bc True))

  --- the Typing Judgement

data HasTypeP where
    HasType :: Env -> Expr -> Type -> HasTypeP -- HasType G e t means G |- e : t

data HasType where 
    TBC   :: Env -> Bool -> HasType
    TIC   :: Env -> Int -> HasType
    TVar1 :: Env -> Vname -> Type -> HasType
    TVar2 :: Env -> Vname -> Type -> HasType -> Vname -> Type -> HasType
    TVar3 :: Env -> Vname -> Type -> HasType -> Vname -> Kind -> HasType
    TPrm  :: Env -> Prim -> HasType
    TAbs  :: Env -> Vname -> Type -> Kind -> WFType -> Expr -> Type 
              -> Vname -> HasType -> HasType
    TApp  :: Env -> Expr -> Vname -> Type -> Type -> HasType 
              -> Expr -> HasType -> HasType
    TAbsT :: Env -> Vname -> Kind -> Expr -> Type -> Kind -> Vname
              -> HasType -> WFType -> HasType
    TAppT :: Env -> Expr -> Vname -> Kind -> Type -> HasType -> Type -> WFType -> HasType
    TLet  :: Env -> Expr -> Type -> HasType -> Vname -> Expr
              -> Type -> Kind -> WFType -> Vname -> HasType -> HasType
    TAnn  :: Env -> Expr -> Type -> HasType -> HasType
    TSub  :: Env -> Expr -> Type -> HasType -> Type -> Kind -> WFType -> Subtype -> HasType

{-@ data HasType where
    TBC   :: g:Env -> b:Bool -> ProofOf(HasType g (Bc b) (tybc b))
 |  TIC   :: g:Env -> n:Int -> ProofOf(HasType g (Ic n) (tyic n))
 |  TVar1 :: g:Env -> { x:Vname | not (in_env x g) } -> t:Type 
                -> ProofOf(HasType (Cons x t g) (FV x) (self t x))
 |  TVar2 :: g:Env -> { x:Vname | in_env x g } -> t:Type -> ProofOf(HasType g (FV x) t)
                -> { y:Vname | y != x && not (in_env y g) && not (Set_mem y (free t)) } -> s:Type 
                -> ProofOf(HasType (Cons y s g) (FV x) t)
 |  TVar3 :: g:Env -> { x:Vname | in_env x g } -> t:Type -> ProofOf(HasType g (FV x) t)
                -> { a:Vname | a != x && not (in_env a g) && not (Set_mem a (freeTV t)) } -> k:Kind
                -> ProofOf(HasType (ConsT a k g) (FV x) t)
 |  TPrm  :: g:Env -> c:Prim -> ProofOf(HasType g (Prim c) (ty c))
 |  TAbs  :: g:Env -> x:Vname -> t_x:Type -> k_x:Kind -> ProofOf(WFType g t_x k_x) 
                -> e:Expr -> t:Type 
                -> { y:Vname | not (in_env y g) && not (Set_mem y (fv e)) && not (Set_mem y (ftv e)) &&
                                                 not (Set_mem y (free t)) && not (Set_mem y (freeTV t)) } 
                -> ProofOf(HasType (Cons y t_x g) (unbind x y e) (unbindT x y t))
                -> ProofOf(HasType g (Lambda x e) (TFunc x t_x t))
 |  TApp  :: g:Env -> e:Expr -> x:Vname -> t_x:Type -> t:Type
                -> ProofOf(HasType g e (TFunc x t_x t)) 
                -> e':Expr -> ProofOf(HasType g e' t_x) 
                -> ProofOf(HasType g (App e e') (TExists x t_x t))
 |  TAbsT :: g:Env -> a:Vname -> k:Kind -> e:Expr -> t:Type -> k_t:Kind
                -> { a':Vname | not (in_env a' g) && not (Set_mem a' (fv e)) && not (Set_mem a' (ftv e)) }
                -> ProofOf(HasType (ConsT a' k g) (unbind_tv a a' e) (unbind_tvT a a' t))
                -> ProofOf(WFType  (ConsT a' k g) (unbind_tvT a a' t) k_t)
                -> ProofOf(HasType g (LambdaT a k e) (TPoly a k t))
 |  TAppT :: g:Env -> e:Expr -> a:Vname -> k:Kind -> s:Type
                -> ProofOf(HasType g e (TPoly a k s)) -> t:Type -> ProofOf(WFType g t k)
                -> ProofOf(HasType g (AppT e t) (tsubBTV a t s))
 |  TLet  :: g:Env -> e_x:Expr -> t_x:Type -> ProofOf(HasType g e_x t_x)
                -> x:Vname -> e:Expr -> t:Type -> k:Kind -> ProofOf(WFType g t k)
                -> { y:Vname | not (in_env y g) && not (Set_mem y (fv e)) && not (Set_mem y (ftv e)) &&
                                                 not (Set_mem y (free t)) && not (Set_mem y (freeTV t)) }
                -> ProofOf(HasType (Cons y t_x g) (unbind x y e) (unbindT x y t))
                -> ProofOf(HasType g (Let x e_x e) t)
 |  TAnn  :: g:Env -> e:Expr -> t:Type -> ProofOf(HasType g e t)
                -> ProofOf(HasType g (Annot e t) t)
 |  TSub  :: g:Env -> e:Expr -> s:Type -> ProofOf(HasType g e s) -> t:Type -> k:Kind
                -> ProofOf(WFType g t k) -> ProofOf(Subtype g s t) 
                -> ProofOf(HasType g e t) @-} 

{-@ lazy typSize @-}
{-@ measure typSize @-}
{-@ typSize :: HasType -> { v:Int | v >= 0 } @-}
typSize :: HasType -> Int
typSize (TBC {})                               = 1
typSize (TIC {})                               = 1
typSize (TVar1 {})                             = 1
typSize (TVar2 _ _ _ p_x_b _ _)                = (typSize p_x_b)   + 1
typSize (TVar3 _ _ _ p_x_b _ _)                = (typSize p_x_b)   + 1
typSize (TPrm {})                              = 1
typSize (TAbs _ _ _ _ _ _ _ _ p_e_b')          = (typSize p_e_b')  + 1
typSize (TApp _ _ _ _ _ p_e_bb' _ p_e'_b)      = (typSize p_e_bb') + (typSize p_e'_b)   + 1
typSize (TAbsT _ _ _ _ _ _ _ p_e_t _)          = (typSize p_e_t)   + 1
typSize (TAppT _ _ _ _ _ p_e_as _ _)           = (typSize p_e_as)  + 1
typSize (TLet _ _ _ p_ex_b _ _ _ _ _ _ p_e_b') = (typSize p_ex_b)  + (typSize p_e_b')   + 1
typSize (TAnn _ _ _ p_e_b)                     = (typSize p_e_b)   + 1
typSize (TSub _ _ _ p_e_s _ _ _ p_s_t)         = (typSize p_e_s)   + (subtypSize p_s_t) + 1


------------------------------------------------------------------------------
----- | SUBTYPING
------------------------------------------------------------------------------

data SubtypeP where
    Subtype :: Env -> Type -> Type -> SubtypeP

data Subtype where
    SBase :: Env -> Vname -> Basic -> Pred -> Vname -> Pred -> Vname -> Entails -> Subtype
    SFunc :: Env -> Vname -> Type -> Vname -> Type -> Subtype
               -> Type -> Type -> Vname -> Subtype -> Subtype
    SWitn :: Env -> Expr -> Type -> HasType -> Type -> Vname -> Type
               -> Subtype -> Subtype
    SBind :: Env -> Vname -> Type -> Type -> Type -> Vname -> Subtype -> Subtype
    SPoly :: Env -> Vname -> Kind -> Type -> Vname -> Type -> Vname -> Subtype -> Subtype

-- edited SFunc 5/5/20: was -> { x2:Vname | not (in_Env x2 g) }. x2 is a BV so there's no
--     possibility for collision with the FV's in the environment g.
{-@ data Subtype where
    SBase :: g:Env -> v1:Vname -> b:Basic -> p1:Pred -> v2:Vname -> p2:Pred 
               -> { y:Vname | not (in_env y g) && not (Set_mem y (fv p2)) }
               -> ProofOf(Entails ( Cons y (TRefn b v1 p1) g) (unbind v2 y p2))
               -> ProofOf(Subtype g (TRefn b v1 p1) (TRefn b v2 p2))
 |  SFunc :: g:Env -> x1:Vname -> s1:Type -> x2:Vname -> s2:Type
               -> ProofOf(Subtype g s2 s1) -> t1:Type -> t2:Type
               -> { y:Vname | not (in_env y g) && not (Set_mem y (free t1)) 
                                               && not (Set_mem y (free t2)) }
               -> ProofOf(Subtype (Cons y s2 g) (unbindT x1 y t1) (unbindT x2 y t2))
               -> ProofOf(Subtype g (TFunc x1 s1 t1) (TFunc x2 s2 t2))
 |  SWitn :: g:Env -> e:Value  -> t_x:Type -> ProofOf(HasType g e t_x) 
               -> t:Type -> x:Vname -> t':Type -> ProofOf(Subtype g t (tsubBV x e t'))
               -> ProofOf(Subtype g t (TExists x t_x t'))
 |  SBind :: g:Env -> x:Vname -> t_x:Type -> t:Type -> {t':Type | not Set_mem x (tfreeBV t')} 
               -> { y:Vname | not (in_env y g) && not (Set_mem y (free t))
                                               && not (Set_mem y (free t')) }
               -> ProofOf(Subtype (Cons y t_x g) (unbindT x y t) t')
               -> ProofOf(Subtype g (TExists x t_x t) t')
 |  SPoly :: g:Env -> a1:Vname -> k:Kind -> t1:Type -> a2:Vname -> t2:Type 
               -> { a:Vname | not (in_env a g) && not (Set_mem a (freeTV t1))
                                               && not (Set_mem a (freeTV t2)) }
               -> ProofOf(Subtype (ConsT a k g) (unbind_tvT a1 a t1) (unbind_tvT a2 a t2))
               -> ProofOf(Subtype g (TPoly a1 k t1) (TPoly a2 k t2))
@-}

{-@ lazy subtypSize @-}
{-@ measure subtypSize @-}
{-@ subtypSize :: Subtype -> { v:Int | v >= 0 } @-}
subtypSize :: Subtype -> Int
subtypSize (SBase {})                              = 1
subtypSize (SFunc _ _ _ _ _ p_s2_s1 _ _ _ p_t1_t2) = (subtypSize p_s2_s1) + (subtypSize p_t1_t2) + 1
subtypSize (SWitn _ _ _ p_e_tx _ _ _ p_t_t')       = (subtypSize p_t_t')  + (typSize p_e_tx)     + 1
subtypSize (SBind _ _ _ _ _ _ p_t_t')              = (subtypSize p_t_t')  + 1
subtypSize (SPoly _ _ _ _ _ _ _ p_t1_t2)           = (subtypSize p_t1_t2) + 1 

-- perhaps move this somewhere else later
{-@ reflect maxBTV @-}
{-@ maxBTV :: FType -> { v:Int | v >= 0 } @-}
maxBTV :: FType -> Int
maxBTV (FTBasic _)      = 0
maxBTV (FTFunc   t_x t) = max (maxBTV t_x) (maxBTV t)
maxBTV (FTPoly a k   t) = (maxBTV t) + 1

{-@ reflect normalize @-}
{-@ normalize :: FType -> FType @-}
normalize :: FType -> FType
normalize (FTBasic b)      = FTBasic b
normalize (FTFunc   t_x t) = FTFunc    t_x t
normalize (FTPoly a k   t) = FTPoly  a' k  (ftsubBV a (FTBasic (BTV a')) t)
  where
    a' = maxBTV (FTPoly a k t)


-------------------------------------------------------------------------
----- | CLOSING SUBSTITUTIONS 
-------------------------------------------------------------------------

-- closing substitutions (i.e. th(x), th(e), th(t)) proceed from the top/right of
--   the typing env downwards/leftwards. In order for a closing substitution to be
--   "well formed" it must be an element of the denotation the corresponding enivornment

data CSubst = CEmpty
            | CCons  Vname Expr CSubst
            | CConsT Vname Type CSubst
  deriving (Show)
{-@ data CSubst  where
    CEmpty :: CSubst
  | CCons  :: x:Vname -> { v:Value | Set_emp (fv v) && Set_emp (ftv v) && 
                                     Set_emp (freeBV v) && Set_emp (freeBTV v) } 
                      -> { th:CSubst | not (in_csubst x th ) } 
                      -> { th':CSubst | bindsC th' == Set_cup (Set_sng x) (bindsC th) } 
  | CConsT :: a:Vname -> { t:Type | Set_emp (free t) && Set_emp (freeTV t) &&
                                    Set_emp (tfreeBV t) && Set_emp (tfreeBTV t) }
                      -> { th:CSubst | not (in_csubst a th) }
                      -> { th':CSubst | bindsC th' == Set_cup (Set_sng a) (bindsC th) } @-}

{-@ reflect bindsC @-}
bindsC :: CSubst -> S.Set Vname
bindsC CEmpty          = S.empty
bindsC (CCons  x v th) = S.union (S.singleton x) (bindsC th)
bindsC (CConsT a t th) = S.union (S.singleton a) (bindsC th)

{-@ reflect in_csubst @-}
in_csubst :: Vname -> CSubst -> Bool
in_csubst x th = S.member x (bindsC th)

{-@ reflect bound_inC @-}
bound_inC :: Vname -> Expr -> CSubst -> Bool
bound_inC x v CEmpty                              = False
bound_inC x v (CCons y v' th) | (x == y)          = (v == v')
                              | otherwise         = bound_inC x v th
bound_inC x v (CConsT a t th) | (x == a)          = False
                              | otherwise         = bound_inC x v th

{-@ reflect tv_bound_inC @-}
tv_bound_inC :: Vname -> Type -> CSubst -> Bool
tv_bound_inC a t CEmpty                                = False
tv_bound_inC a t (CCons  y  v' th) | (a == y)          = False
                                   | otherwise         = tv_bound_inC a t th
tv_bound_inC a t (CConsT a' t' th) | (a == a')         = (t == t')
                                   | otherwise         = tv_bound_inC a t th

{-{-@ measure uniqueC @-}
uniqueC :: CSubst -> Bool
uniqueC CEmpty         = True
uniqueC (CCons x v th) = (uniqueC th) && not (S.member x (bindsC th))

{-@ lem_env_uniqueC :: th:CSubst -> { pf:_ | uniqueC th } @-}
lem_env_uniqueC :: CSubst -> Proof
lem_env_uniqueC CEmpty         = ()
lem_env_uniqueC (CCons x v th) = () ? lem_env_uniqueC th-}

{-@ reflect csubst @-}
csubst :: CSubst -> Expr -> Expr
csubst CEmpty          e = e
csubst (CCons  x v th) e = csubst th (subFV x v e)
csubst (CConsT a t th) e = csubst th (subFTV a t e)

-- Idea: ctsubst th t = foldr (\(x,e) t' -> tsubFV x e t') t th 
{-@ reflect ctsubst @-}
ctsubst :: CSubst -> Type -> Type
ctsubst CEmpty           t = t
ctsubst (CCons  x v  th) t = ctsubst th (tsubFV x v t)
ctsubst (CConsT a t' th) t = ctsubst th (tsubFTV a t' t)

{-@ reflect concatCS @-}
{-@ concatCS :: th:CSubst -> { th':CSubst | Set_emp (Set_cap (bindsC th) (bindsC th')) }
                          -> { thC:CSubst | bindsC thC == Set_cup (bindsC th) (bindsC th') } @-}
concatCS :: CSubst -> CSubst -> CSubst
concatCS th CEmpty           = th
concatCS th (CCons  x v th') = CCons x v (concatCS th th')
concatCS th (CConsT a t th') = CConsT a t (concatCS th th')


{-@ reflect change_varCS @-}
{-@ change_varCS :: th:CSubst ->  { x:Vname | in_csubst x th } 
        -> { y:Vname | y == x || not (in_csubst y th) } 
        -> { th':CSubst | bindsC th' == Set_cup (Set_sng y) (Set_dif (bindsC th) (Set_sng x))} @-} 
change_varCS :: CSubst -> Vname -> Vname -> CSubst
change_varCS CEmpty            x y = CEmpty
change_varCS (CCons  z v_z th) x y | ( x == z ) = CCons  y v_z th
                                   | otherwise  = CCons  z v_z (change_varCS th x y)
change_varCS (CConsT a t_a th) x y | ( x == a ) = CConsT y t_a th
                                   | otherwise  = CConsT a t_a (change_varCS th x y)

{-@ reflect remove_fromCS @-}
{-@ remove_fromCS :: th:CSubst -> { x:Vname | in_csubst x th}
        -> { th':CSubst | bindsC th' == Set_dif (bindsC th) (Set_sng x) } @-}
remove_fromCS :: CSubst -> Vname -> CSubst
remove_fromCS (CCons  z v_z th) x | ( x == z ) = th
                                  | otherwise  = CCons  z v_z (remove_fromCS th x)
remove_fromCS (CConsT a t_a th) x | ( x == a ) = th
                                  | otherwise  = CConsT a t_a (remove_fromCS th x)


-------------------------------------------------------------------------
----- | ENTAILMENTS and DENOTATIONAL SEMANTICS 
-------------------------------------------------------------------------

data EntailsP where
    Entails :: Env -> Pred -> EntailsP

data Entails where
    EntPred :: Env -> Pred -> (CSubst -> DenotesEnv -> EvalsTo) -> Entails

{-@ data Entails where
    EntPred :: g:Env -> p:Pred 
               -> (th:CSubst -> ProofOf(DenotesEnv g th) 
                             -> ProofOf(EvalsTo (csubst th p) (Bc True)) )
               -> ProofOf(Entails g p) @-} 

-- We say the proposition ValueDenoted e t holds if there exists a value v such that
--     * e \many v, and
--     * v \in [[ t ]].
data ValueDenotedP where
    ValueDenoted :: Expr -> Type -> ValueDenotedP

{-@ data ValueDenoted where 
    ValDen :: e:Expr -> t:Type -> v:Value -> ProofOf(EvalsTo e v)
                                  -> ProofOf(Denotes t v) -> ProofOf(ValueDenoted e t) @-}
data ValueDenoted where     
    ValDen :: Expr -> Type -> Expr -> EvalsTo -> Denotes -> ValueDenoted


data DenotesP where 
    Denotes :: Type -> Expr -> DenotesP    -- e \in [[t]]

data Denotes where
    DRefn :: Basic -> Vname -> Pred -> Expr -> HasFType -> EvalsTo -> Denotes
    DFunc :: Vname -> Type -> Type -> Expr -> HasFType
              -> (Expr -> Denotes -> ValueDenoted) -> Denotes
    DExis :: Vname -> Type -> Type -> Expr -> HasFType
              -> Expr -> Denotes -> Denotes -> Denotes
    DPoly :: Vname -> Kind -> Type -> Expr -> HasFType
              -> (Type -> WFType -> ValueDenoted) -> Denotes
{-@ data Denotes where
    DRefn :: b:Basic -> x:Vname -> p:Pred -> v:Value  
              -> ProofOf(HasFType FEmpty v (FTBasic b))
              -> ProofOf(EvalsTo (subBV x v p) (Bc True)) 
              -> ProofOf(Denotes (TRefn b x p) v)
  | DFunc :: x:Vname -> t_x:Type -> t:Type -> v:Value  
              -> ProofOf(HasFType FEmpty v (erase (TFunc x t_x t)))
              -> ( v_x:Value -> ProofOf(Denotes t_x v_x)
                             -> ProofOf(ValueDenoted (App v v_x) (tsubBV x v_x t)) ) 
              -> ProofOf(Denotes (TFunc x t_x t) v)
  | DExis :: x:Vname -> t_x:Type -> t:Type -> v:Value 
              -> ProofOf(HasFType FEmpty v (erase t)) 
              -> v_x:Value -> ProofOf(Denotes t_x v_x)
              -> ProofOf(Denotes (tsubBV x v_x t) v)
              -> ProofOf(Denotes (TExists x t_x t) v)  
  | DPoly :: a:Vname -> k:Kind -> t:Type -> v:Value
              -> ProofOf(HasFType FEmpty v (FTPoly a k (erase t)))
              -> ( t_a:Type -> ProofOf(WFType Empty t_a k) 
                            -> ProofOf(ValueDenoted (AppT v t_a) (tsubBTV a t_a t)) )
              -> ProofOf(Denotes (TPoly a k t) v) @-} 

{-@ get_ftyp_from_den :: t:Type -> v:Value -> ProofOf(Denotes t v)
              -> ProofOf(HasFType FEmpty v (erase t)) @-}
get_ftyp_from_den :: Type -> Expr -> Denotes -> HasFType    
get_ftyp_from_den t v (DRefn _ _ _ _ pf_v_b _)     = pf_v_b
get_ftyp_from_den t v (DFunc _ _ _ _ pf_v_b _)     = pf_v_b
get_ftyp_from_den t v (DExis _ _ _ _ pf_v_b _ _ _) = pf_v_b
get_ftyp_from_den t v (DPoly _ _ _ _ pf_v_b _)     = pf_v_b

{-@ lem_den_nofv :: v:Value -> t:Type -> ProofOf(Denotes t v) 
        -> { pf:_ | Set_emp (fv v) } @-}
lem_den_nofv :: Expr -> Type -> Denotes -> Proof
lem_den_nofv v t den_t_v = lem_fv_subset_bindsF FEmpty v (erase t) pf_v_bt
  where
    pf_v_bt = get_ftyp_from_den t v den_t_v

{-@ get_obj_from_dfunc :: x:Vname -> s:Type -> t:Type -> v:Value 
        -> ProofOf(Denotes (TFunc x s t) v) -> v':Value 
        -> ProofOf(Denotes s v') -> ProofOf(ValueDenoted (App v v') (tsubBV x v' t)) @-}  
get_obj_from_dfunc :: Vname -> Type -> Type -> Expr -> Denotes 
                                    -> Expr -> Denotes -> ValueDenoted
get_obj_from_dfunc x s t v (DFunc _ _ _ _ _ prover) v' den_s_v' = prover v' den_s_v' 

-- Denotations of Environments, [[g]]. There are two cases:
--   1. [[ Empty ]] = { CEmpty }.
--   2. [[ Cons x t g ]] = { CCons x v_x th | Denotes th(t) v_x && th \in [[ g ]] }
data DenotesEnvP where 
    DenotesEnv :: Env -> CSubst -> DenotesEnvP 

data DenotesEnv where
    DEmp :: DenotesEnv
    DExt :: Env -> CSubst -> DenotesEnv -> Vname -> Type -> Expr -> Denotes -> DenotesEnv
    DExtT :: Env -> CSubst -> DenotesEnv -> Vname -> Kind -> Type -> WFType -> DenotesEnv
{-@ data DenotesEnv where 
    DEmp  :: ProofOf(DenotesEnv Empty CEmpty)
 |  DExt  :: g:Env -> th:CSubst -> ProofOf(DenotesEnv g th) 
               -> { x:Vname | not (in_env x g) } -> t:Type 
               -> { v:Value | Set_emp (fv v) && Set_emp (ftv v) && Set_emp (freeBV v) && Set_emp (freeBTV v) }
               -> ProofOf(Denotes (ctsubst th t) v)
               -> ProofOf(DenotesEnv (Cons x t g) (CCons x v th)) 
 |  DExtT :: g:Env -> th:CSubst -> ProofOf(DenotesEnv g th)
               -> { a:Vname | not (in_env a g) } -> k:Kind
               -> { t:Type  | Set_emp (free t) && Set_emp (freeTV t) && 
                              Set_emp (tfreeBV t) && Set_emp (tfreeBTV t) }
               -> ProofOf(WFType Empty (ctsubst th (TRefn (FTV a) 1 (Bc True))) k)
               -> ProofOf(DenotesEnv (ConsT a k g) (CConsT a t th)) @-}

{-@ lem_binds_env_th :: g:Env -> th:CSubst -> ProofOf(DenotesEnv g th) -> { pf:_ | binds g == bindsC th } @-}
lem_binds_env_th :: Env -> CSubst -> DenotesEnv -> Proof
lem_binds_env_th g th DEmp                                      = ()
lem_binds_env_th g th (DExt g' th' den_g'_th' x t v den_th't_v) = () ? lem_binds_env_th g' th' den_g'_th'
lem_binds_env_th g th (DExtT {})
    = undefined