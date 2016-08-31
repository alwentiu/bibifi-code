module Widgets where

import Control.Monad

import Import
import PostDependencyType

import qualified Database.Esqueleto as E

buildSubmission :: Entity BuildSubmission -> ContestId -> Bool -> LWidget
buildSubmission (Entity bsId bs) cId public = do
    let status = prettyBuildStatus $ buildSubmissionStatus bs
    time <- lLift $ lift $ displayTime $ buildSubmissionTimestamp bs
    judgementW <- do
        judgementM <- handlerToWidget $ runDB $ getBy $ UniqueBuildJudgement bsId
        extractWidget $ case judgementM of
            Nothing ->
                mempty
            Just (Entity jId j) -> 
                let ruling = case buildJudgementRuling j of
                      Nothing ->
                        [shamlet|
                            <span>
                                Pending
                        |]
                      Just True ->
                        [shamlet|
                            <span class="text-success">
                                Passed
                        |]
                      Just False ->
                        [shamlet|
                            <span class="text-danger">
                                Failed
                        |]
                in
                let comments = case buildJudgementComments j of
                      Nothing ->
                        dash
                      Just c ->
                        toHtml c
                in
                do
                [whamlet|
                    <div class="form-group">
                        <label class="col-xs-3 control-label">
                            Judgment
                        <div class="col-xs-9">
                            <p class="form-control-static">
                                #{ruling}
                |]
                when (not public) $
                    [whamlet|
                        <div class="form-group">
                            <label class="col-xs-3 control-label">
                                Judge comments
                            <div class="col-xs-9">
                                <p class="form-control-static">
                                    #{comments}
                    |]
    [whamlet|
        <form class="form-horizontal">
            <div class="form-group">
                <label class="col-xs-3 control-label">
                    Submission hash
                <div class="col-xs-9">
                    <p class="form-control-static">
                        #{buildSubmissionCommitHash bs}
            <div class="form-group">
                <label class="col-xs-3 control-label">
                    Timestamp
                <div class="col-xs-9">
                    <p class="form-control-static">
                        #{time}
            <div class="form-group">
                <label class="col-xs-3 control-label">
                    Status
                <div class="col-xs-9">
                    <p class="form-control-static">
                        #{status}
            ^{judgementW}
    |]
    when (not public) $ do
        case (buildSubmissionStdout bs, buildSubmissionStderr bs) of
            (Just stdout, Just stderr) -> 
                [whamlet|
                    <h4>
                        Build Standard Output
                    <samp>
                        #{stdout}
                    <h4>
                        Build Standard Error
                    <samp>
                        #{stderr}
                |]
            _ ->
                mempty
    if (buildSubmissionStatus bs) == BuildBuilt then
        let renderCores ((Entity _ test), mbr') = 
              let result = case mbr' of 
                    Nothing ->
                        prettyPassResult False
                    Just (Entity _ mbr) ->
                        prettyPassResult $ buildCoreResultPass mbr
              in
              [whamlet'|
                  <tr>
                      <td>
                          #{contestCoreTestName test}
                      <td>
                          Correctness
                      <td>
                          #{result}
                      <td>
                          #{dash}
              |]
        in
        let renderOpts ((Entity _ test), mbr') =
              let result = case mbr' of 
                    Nothing ->
                        prettyPassResult False
                    Just (Entity _ mbr) ->
                        prettyPassResult $ buildOptionalResultPass mbr
              in
              [whamlet'|
                  <tr>
                      <td>
                          #{contestOptionalTestName test}
                      <td>
                          Optional
                      <td>
                          #{result}
                      <td>
                          #{dash}
              |]
        in
        let renderPerfs ((Entity _ test), mbr') =
              let (result, period) = case mbr' of
                    Nothing ->
                        (prettyPassResult False, dash)
                    Just (Entity _ mbr) ->
                        case buildPerformanceResultTime mbr of
                            Nothing ->
                                ( prettyPassResult False, dash)
                            Just t ->
                                let period' = [shamlet|#{t}|] in
                                ( prettyPassResult True, period')
              in
              let testType = 
                    if contestPerformanceTestOptional test then
                        "Performance" :: String
                    else
                        "Performance*"
              in
              [whamlet'|
                  <tr>
                      <td>
                          #{contestPerformanceTestName test}
                      <td>
                          #{testType}
                      <td>
                          #{result}
                      <td>
                          #{period}
              |]
        in
        do
        coreResults <- handlerToWidget $ runDB 
            -- [lsql| 
            --     select ContestCoreTest.*, BuildCoreResult.* from ContestCoreTest 
            --     left outer join BuildCoreResult on ContestCoreTest.id == BuildCoreResult.test
            --     where ContestCoreTest.contest == #{cId}
            --         and (BuildCoreResult.submission == #{Just bsId} or BuildCoreResult.submission is null)
            --     order by ContestCoreTest.name asc
            -- |]
            $ E.select $ E.from $ \(t `E.LeftOuterJoin` tr) -> do
                E.on ( E.just (t E.^. ContestCoreTestId) E.==. tr E.?. BuildCoreResultTest
                    E.&&. (tr E.?. BuildCoreResultSubmission E.==. E.just (E.val bsId)
                    E.||. E.isNothing (tr E.?. BuildCoreResultId)))
                E.where_ ( t E.^. ContestCoreTestContest E.==. E.val cId)
                E.orderBy [E.asc (t E.^. ContestCoreTestId)]
                return ( t, tr)
        performanceResults <- handlerToWidget $ runDB 
            -- [lsql|
            --     select ContestPerformanceTest.*, BuildPerformanceResult.* from ContestPerformanceTest
            --     left outer join BuildPerformanceResult on ContestPerformanceTest.id == BuildPerformanceResult.test
            --     where ContestPerformanceTest.contest == #{cId}
            --         and (BuildPerformanceResult.submission == #{Just bsId} or BuildPerformanceResult.id is null)
            --     order by ContestPerformanceTest.name asc
            -- |]
            $ E.select $ E.from $ \(t `E.LeftOuterJoin` tr) -> do
                E.on ( E.just (t E.^. ContestPerformanceTestId) E.==. tr E.?. BuildPerformanceResultTest
                    E.&&. ( tr E.?. BuildPerformanceResultSubmission E.==. E.just (E.val bsId)
                    E.||. E.isNothing (tr E.?. BuildPerformanceResultId)))
                E.where_ ( t E.^. ContestPerformanceTestContest E.==. E.val cId)
                E.orderBy [E.asc (t E.^. ContestPerformanceTestId)]
                return ( t, tr)
        optionalResults <- handlerToWidget $ runDB 
            -- [lsql|
            --     select ContestOptionalTest.*, BuildOptionalResult.* from ContestOptionalTest
            --     left outer join BuildOptionalResult on ContestOptionalTest.id == BuildOptionalResult.test
            --     where ContestOptionalTest.contest == #{cId}
            --         and (BuildOptionalResult.submission == #{Just bsId} or BuildOptionalResult.id is null)
            --     order by ContestOptionalTest.name asc
            -- |]
            $ E.select $ E.from $ \(t `E.LeftOuterJoin` tr) -> do
                E.on ( E.just (t E.^. ContestOptionalTestId) E.==. tr E.?. BuildOptionalResultTest
                    E.&&. ( tr E.?. BuildOptionalResultSubmission E.==. E.just (E.val bsId) 
                    E.||. E.isNothing (tr E.?. BuildOptionalResultId)))
                E.where_ ( t E.^. ContestOptionalTestContest E.==. E.val cId)
                E.orderBy [E.asc (t E.^. ContestOptionalTestId)]
                return ( t, tr)
        [whamlet|
            <h3>
                Test Results
        |]
        if ((length coreResults) + (length performanceResults) + (length optionalResults)) == 0 then
            [whamlet|
                <p>
                    No tests found.
            |]
        else
            let cores = mconcat $ map renderCores coreResults in
            let perfs = mconcat $ map renderPerfs performanceResults in
            let opts = mconcat $ map renderOpts optionalResults in
            [whamlet|
                <table class="table table-hover">
                    <thead>
                        <tr>
                            <th>
                                Test name
                            <th>
                                Test type
                            <th>
                                Result
                            <th>
                                Performance
                    <tbody>
                        ^{cores}
                        ^{perfs}
                        ^{opts}
            |]
    else
        mempty
