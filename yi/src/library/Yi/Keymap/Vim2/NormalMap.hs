module Yi.Keymap.Vim2.NormalMap
  ( defNormalMap
  ) where

import Yi.Prelude
import Prelude ()

import Data.Char
import Data.Maybe (fromMaybe)

import Yi.Buffer hiding (Insert)
import Yi.Core (quitEditor)
import Yi.Editor
import Yi.Event
import Yi.Keymap.Keys
import Yi.Keymap.Vim2.Common
import Yi.Keymap.Vim2.Eval
import Yi.Keymap.Vim2.StateUtils
import Yi.Keymap.Vim2.Utils

mkDigitBinding :: Char -> VimBinding
mkDigitBinding c = mkBindingE' Normal (char c, return (), mutate, Continue)
    where mutate (VimState m Nothing a rm r es) = VimState m (Just d) a rm r es
          mutate (VimState m (Just count) a rm r es) = VimState m (Just $ count * 10 + d) a rm r es
          d = ord c - ord '0'

defNormalMap :: [VimBinding]
defNormalMap = [mkBindingY Normal (spec (KFun 10), quitEditor, id)] ++ pureBindings

pureBindings :: [VimBinding]
pureBindings =
    [zeroBinding, repeatBinding] ++
    fmap (mkBindingE' Normal)
        [ (char 'x', cutChar Forward =<< getCountE, resetCount, Finish)
        , (char 'X', cutChar Backward =<< getCountE, resetCount, Finish)
        ] ++
    fmap (mkBindingE Normal)
        [ (char 'h', vimMoveE (VMChar Backward), resetCount)
        , (char 'l', vimMoveE (VMChar Forward), resetCount)
        , (char 'j', vimMoveE (VMLine Forward), resetCount)
        , (char 'k', vimMoveE (VMLine Backward), resetCount)

        -- Word motions
        , (char 'w', vimMoveE (VMWordStart Forward), resetCount)
        , (char 'b', vimMoveE (VMWordStart Backward), resetCount)
        , (char 'e', vimMoveE (VMWordEnd Forward), resetCount)
        , (char 'W', vimMoveE (VMWORDStart Forward), resetCount)
        , (char 'B', vimMoveE (VMWORDStart Backward), resetCount)
        , (char 'E', vimMoveE (VMWORDEnd Forward), resetCount)

        -- Intraline stuff
        , (char '$', vimMoveE VMEOL, resetCount)
        , (char '^', vimMoveE VMNonEmptySOL, resetCount)

        -- Transition to insert mode
        , (char 'i', return (), switchMode Insert)
        , (char 'I', vimMoveE VMNonEmptySOL, switchMode Insert)
        , (char 'a', withBuffer0 rightB, switchMode Insert)
        , (char 'A', withBuffer0 moveToEol, switchMode Insert)
        , (char 'o', withBuffer0 $ do
                         moveToEol
                         insertB '\n'
            , switchMode Insert)
        , (char 'O', withBuffer0 $ do
                         moveToSol
                         insertB '\n'
                         leftB
            , switchMode Insert)
        , (spec KEsc, return (), resetCount)
        , (ctrlCh 'c', return (), resetCount)

        -- Changing
        , (char 'c', return (), switchMode Insert) -- TODO
        , (char 'C', return (), switchMode Insert) -- TODO
        , (char 's', return (), id) -- TODO
        , (char 'S', return (), id) -- TODO

        -- Replacing
        , (char 'r', return (), switchMode ReplaceSingleChar)
        , (char 'R', return (), switchMode Replace)

        -- Deletion
        , (char 'd', return (), id) -- TODO
        , (char 'D', return (), id) -- TODO

        -- Yanking
        , (char 'y', return (), id) -- TODO
        , (char 'Y', return (), id) -- TODO

        -- Pasting
        , (char 'p', return (), id) -- TODO
        , (char 'P', return (), id) -- TODO

        -- Search
        , (char '/', return (), id) -- TODO
        , (char '?', return (), id) -- TODO
        , (char '*', return (), id) -- TODO
        , (char '#', return (), id) -- TODO
        , (char 'n', return (), id) -- TODO
        , (char 'N', return (), id) -- TODO
        , (char 'f', return (), id) -- TODO
        , (char 'F', return (), id) -- TODO
        , (char 't', return (), id) -- TODO
        , (char 'T', return (), id) -- TODO

        -- Transition to visual
        , (char 'v', return (), id) -- TODO
        , (char 'V', return (), id) -- TODO
        , (ctrlCh 'v', return (), id) -- TODO

        -- Repeat
        , (char '&', return (), id) -- TODO

        -- Transition to ex
        , (char ':', return (), id) -- TODO

        -- Undo
        , (char 'u', return (), id) -- TODO
        , (char 'U', return (), id) -- TODO
        , (ctrlCh 'r', return (), id) -- TODO

        -- Indenting
        , (char '<', return (), id) -- TODO
        , (char '>', return (), id) -- TODO

        -- unsorted TODO
        , (char 'g', return (), id)
        , (char 'G', return (), id)
        , (char 'm', return (), id)
        , (char '[', return (), id)
        , (char ']', return (), id)
        , (char '{', return (), id)
        , (char '}', return (), id)
        , (char '-', return (), id)
        , (char '+', return (), id)
        , (char '~', return (), id)
        , (char '"', return (), id)
        , (char 'q', return (), id)
        , (spec KEnter, return (), id)
        ]
    ++ fmap mkDigitBinding ['1' .. '9']

zeroBinding :: VimBinding
zeroBinding = VimBindingE prereq action
    where prereq ev state = ev == char '0' && (vsMode state == Normal)
          action _ = do
              currentState <- getDynamic
              case (vsCount currentState) of
                  Just c -> do
                      setDynamic $ currentState { vsCount = Just (10 * c) }
                      return Continue
                  Nothing -> do
                      vimMoveE VMSOL
                      setDynamic $ resetCount currentState
                      return Drop

repeatBinding :: VimBinding
repeatBinding = VimBindingE prereq action
    where prereq ev state = ev == char '.' && (vsMode state == Normal)
          action _ = do
                currentState <- getDynamic
                case vsRepeatableAction currentState of
                    Nothing -> return ()
                    Just (RepeatableAction prevCount actionString) -> do
                        let count = fromMaybe prevCount (vsCount currentState)
                        scheduleActionStringForEval $ show count ++ actionString
                return Drop

cutChar :: Direction -> Int -> EditorM ()
cutChar dir count = withBuffer0 $ do
    p0 <- pointB
    (if dir == Forward then moveXorEol else moveXorSol) count
    p1 <- pointB
    deleteRegionB $ mkRegion p0 p1
    leftOnEol