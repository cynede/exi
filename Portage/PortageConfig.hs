{-|
    Maintainer  :  Andres Loeh <kosmikus@gentoo.org>
    Stability   :  provisional
    Portability :  haskell98

    Create the portage configuration.
-}

module Portage.PortageConfig
  where

import System.IO

import Portage.Config
import Portage.Tree
import Portage.Use
import Portage.UseDefaults
import Portage.Mask
import Portage.PackageKeywords
import Portage.PackageUse
import Portage.PackageProvided
import Portage.Dependency
import Portage.Virtual

data PortageConfig =  PortageConfig
                        {
                           config    ::  Config,
                           tree      ::  Tree,
                           inst      ::  Tree,
                           itree     ::  Tree,
                           virtuals  ::  DepAtom -> DepTerm
                        }

-- | Portage configuration is read in the following order, in increasing priority:
--   global < profile < user < environment < (package specific)
portageConfig :: IO PortageConfig
portageConfig = 
    do
        -- read basic configuration data
        global    <-  getGlobalConfig
        profiles  <-  getProfileConfigs
        user      <-  getUserConfig
        env       <-  getEnvironmentConfig
        let merged  =  foldl1 mergeConfig (global : profiles ++ [user,env])
        -- read installed tree, because that's required to determine virtuals
        -- USE data
        inst      <-  createInstalledTree merged
        uprov     <-  profileProvided
        inst      <-  return $ foldl (flip addProvided) inst uprov
        ud        <-  computeUseDefaults inst
        -- the following is the "final" basic configuration
        let cfg     =  merged { use = arch merged : mergeUse (use merged) ud }
        -- now read the portage tree(s)
        cats      <-  categories cfg
        tree      <-  fixIO (\r ->  do
                                        pt  <-  createTree cfg (portDir cfg) cats (eclasses r)
                                        po  <-  mapM (\t -> createTree cfg t cats (eclasses r)) (overlays cfg)
                                        return $ foldl overlayTree pt po)
        -- hardmasking (not on the installed tree!)
        gmask     <-  globalMask cfg
        pmask     <-  profileMask
        umask     <-  userMask
        uunmask   <-  userUnMask
        tree      <-  return $ foldl (flip performMask)      tree (concat [gmask, pmask, umask])
        tree      <-  return $ foldl (flip performUnMask)    tree uunmask
        -- keyword distribution (also not on the installed tree)
        ukey      <-  userKeywords
        tree      <-  return $ foldl (flip performKeywords)  tree ukey
        -- USE flag distribution (again, not on the installed tree)
        uuse      <-  userUseFlags
        tree      <-  return $ foldl (flip performUseFlags)  tree uuse
        -- keyword masking
        tree      <-  return $ traverseTree (keywordMask cfg) tree
        -- virtuals
        pvirt     <-  profileVirtuals
        let itree     =  overlayInstalledTree tree inst
        let virtuals  =  computeVirtuals pvirt inst
        return (PortageConfig cfg tree inst itree virtuals)
