##########################GO-LICENSE-START################################
# Copyright 2016 ThoughtWorks, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##########################GO-LICENSE-END##################################

require 'rails_helper'

def stub_current_config
  cruise_config = double("cruise config")
  expect(cruise_config).to receive(:getMd5).and_return("current-md5")
  expect(@go_config_service).to receive(:getCurrentConfig).and_return(cruise_config)
end

describe StagesController do

  include StageModelMother
  include ApplicationHelper
  include JobMother

  before(:each) do
    controller.go_cache.clear
    @stage_service = double('stage service')
    @shine_dao = double('shine dao')
    @material_service = double('material service')
    @job_presentation_service = double("job presentation service")
    @cruise_config = BasicCruiseConfig.new
    @go_config_service = double("go config service")
    @user = Username.new(CaseInsensitiveString.new("foo"))
    @status = double(HttpOperationResult)
    allow(HttpOperationResult).to receive(:new).and_return(@status)
    @localized_result = double(HttpLocalizedOperationResult)
    @subsection_result = SubsectionLocalizedOperationResult.new
    allow(HttpLocalizedOperationResult).to receive(:new).and_return(@localized_result)
    allow(controller).to receive(:current_user).and_return(@user)
    allow(controller).to receive(:stage_service).and_return(@stage_service)
    allow(controller).to receive(:shine_dao).and_return(@shine_dao)
    allow(controller).to receive(:material_service).and_return(@material_service)
    allow(controller).to receive(:job_presentation_service).and_return(@job_presentation_service)
    allow(controller).to receive(:go_config_service).and_return(@go_config_service)
    allow(controller).to receive(:populate_config_validity)

    allow(@go_config_service).to receive(:findGroupNameByPipeline).and_return(nil)
    allow(@go_config_service).to receive(:isPipelineEditable)

    @pim = PipelineHistoryMother.singlePipeline("pipline-name", StageInstanceModels.new)
    allow(controller).to receive(:pipeline_history_service).and_return(@pipeline_history_service=double())
    allow(controller).to receive(:pipeline_lock_service).and_return(@pipieline_lock_service=double())
    @pipeline_identifier = PipelineIdentifier.new("blah", 1, "label")
    allow(@localized_result).to receive(:isSuccessful).and_return(true)
  end

  describe "stage" do

    before do
      @stage_summary_model = StageSummaryModel.new(stage = StageMother.passedStageInstance("stage", "dev", "pipeline-name"), nil, JobDurationStrategy::ALWAYS_ZERO, nil)
      stage.setPipelineId(100)
      allow(@stage_service).to receive(:failingTests).and_return(StageTestRuns.new(12, 0, 0))
      allow(@stage_service).to receive(:findStageSummaryByIdentifier).and_return(@stage_summary_model)
      allow(@stage_service).to receive(:findLatestStage).and_return(:latest_stage)
      allow(@stage_service).to receive(:findStageHistoryPage).and_return(@stage_history = stage_history_page(3))
      allow(@pipeline_history_service).to receive(:validate).with("pipeline", @user, @status)
      allow(@pipeline_history_service).to receive(:findPipelineInstance).and_return(:pim)
      allow(@pipieline_lock_service).to receive(:lockedPipeline).and_return(@pipeline_identifier)
      allow(@status).to receive(:canContinue).and_return(true)
    end

    describe "tabs" do
      before do
        stub_current_config
      end
      it "should render overview tab by default" do
        get :overview, :pipeline_name => "pipeline", :pipeline_counter => "2", :stage_name => "stage", :stage_counter => "3"
        expect(controller.params[:action]).to eq "overview"
      end

      it "should assign appropriate tab" do
        expect(@go_config_service).to receive(:stageExists).with("pipeline", "stage").and_return(true)
        expect(@go_config_service).to receive(:stageHasTests).with("pipeline", "stage").and_return(false)
        get :tests, :pipeline_name => "pipeline", :pipeline_counter => "2", :stage_name => "stage", :stage_counter => "3"
        expect(controller.params[:action]).to eq "tests"
      end

    end

    it "should load stage" do
      stub_current_config
      stage_identifier = StageIdentifier.new("pipeline", 2, "stage", "3")
      expect(@stage_service).to receive(:findStageSummaryByIdentifier).with(stage_identifier, @user, @localized_result).and_return(@stage_summary_model)
      expect(@pipeline_history_service).to receive(:findPipelineInstance).with("pipeline", 2, 100, @user, @status).and_return(:pim)
      expect(@pipieline_lock_service).to receive(:lockedPipeline).with("pipeline").and_return(@pipeline_identifier)
      allow(@status).to receive(:canContinue).and_return(true)

      get :overview, :pipeline_name => "pipeline", :pipeline_counter => "2", :stage_name => "stage", :stage_counter => "3"

      expect(assigns(:stage)).to eq @stage_summary_model
    end

    describe "rerun_jobs" do
      before(:each) do
        stage_identifier = StageIdentifier.new("pipeline", 2, "stage", "3")
        expect(@stage_service).to receive(:findStageSummaryByIdentifier).with(stage_identifier, @user, @localized_result).and_return(@stage_summary_model)
        @schedule_service = stub_service(:schedule_service)
        stub_current_config
      end

      it "should rerun jobs" do
        new_stage = StageMother.scheduledStage("pipeline_foo", 10, "stage_bar", 2, "con_job")
        expect(@schedule_service).to receive(:rerunJobs).with(@stage_summary_model.getStage(), ["job_foo", "job_bar", "job_baz"], @status).and_return(new_stage)
        post :rerun_jobs, :jobs => ["job_foo", "job_bar", "job_baz"], :pipeline_name => "pipeline", :pipeline_counter => "2", :stage_name => "stage", :stage_counter => "3", :tab => 'jobs'
        expect(response.status).to eq 302
        expect(response.location).to eq "http://test.host/pipelines/pipeline_foo/10/stage_bar/2/jobs"
      end

      it "should rerun jobs and redirect to overview tab when tab name not given" do
        new_stage = StageMother.scheduledStage("pipeline_foo", 10, "stage_bar", 2, "con_job")
        expect(@schedule_service).to receive(:rerunJobs).with(@stage_summary_model.getStage(), ["job_foo", "job_bar", "job_baz"], @status).and_return(new_stage)
        post :rerun_jobs, :jobs => ["job_foo", "job_bar", "job_baz"], :pipeline_name => "pipeline", :pipeline_counter => "2", :stage_name => "stage", :stage_counter => "3"
        expect(response.status).to eq 302
        expect(response.location).to eq "http://test.host/pipelines/pipeline_foo/10/stage_bar/2"
      end

      it "should display error when rerun job fails" do
        expect(@schedule_service).to receive(:rerunJobs).with(@stage_summary_model.getStage(), ["job_foo", "job_bar", "job_baz"], @status) do |*args|
          allow(@status).to receive(:canContinue).and_return(false)
          allow(@status).to receive(:httpCode).and_return(409)
          allow(@status).to receive(:message).and_return("Dammit, it failed again")
        end
        post :rerun_jobs, :jobs => ["job_foo", "job_bar", "job_baz"], :pipeline_name => "pipeline", :pipeline_counter => "2", :stage_name => "stage", :stage_counter => "3", :tab => "jobs"
        expect(response.location).to match(/\/pipelines\/pipeline\/2\/stage\/3\/jobs\?fm=.+/)
        expect(response.status).to eq 302
      end
    end

    it "should resolve url with dots in pipline and stage name" do
      expect(:get => "/pipelines/blah.pipe-line/1/_blah.stage/1").to route_to({:controller => "stages", :action => 'overview', :pipeline_name => "blah.pipe-line", :stage_name => "_blah.stage", :pipeline_counter => "1", :stage_counter => "1"})
      expect(controller.send(:stage_detail_tab_path, :pipeline_counter => "1", :pipeline_name => "blah.pipe-line", :stage_counter => "1", :stage_name => "_blah.stage")).to eq("/pipelines/blah.pipe-line/1/_blah.stage/1")
    end

    it "should render response code returned by the api result" do
      stage_identifier = StageIdentifier.new("pipeline", 2, "stage", "3")
      expect(@stage_service).to receive(:findStageSummaryByIdentifier).with(stage_identifier, @user, @localized_result).and_return(@stage_summary_model)
      expect(@status).to receive(:canContinue).and_return(true)
      expect(@localized_result).to receive(:isSuccessful).and_return(false)
      allow(@localized_result).to receive(:httpCode).and_return(401)
      allow(@localized_result).to receive(:message).and_return("no view permission")
      get :overview, :pipeline_name => "pipeline", :pipeline_counter => "2", :stage_name => "stage", :stage_counter => "3"
      expect(response.status).to eq 401
    end

    it "should render response code returned by the api result" do
      stage_identifier = StageIdentifier.new("pipeline", 2, "stage", "3")
      allow(@pipeline_history_service).to receive(:validate).with("pipeline", @user, @status)

      expect(@status).to receive(:canContinue).and_return(false)
      expect(@status).to receive(:detailedMessage).and_return("Not Found")
      expect(@status).to receive(:httpCode).and_return(404)

      get :overview, :pipeline_name => "pipeline", :pipeline_counter => "2", :stage_name => "stage", :stage_counter => "3"
      expect(response.status).to eq 404
    end

    it "should resolve piplines/stage-locator to the stage action" do
      expect(:get => "/pipelines/pipeline_name/10/stage_name/2").to route_to({:controller => "stages", :action => 'overview', :pipeline_name => "pipeline_name", :stage_name => "stage_name", :pipeline_counter => "10", :stage_counter => "2"})
      expect(controller.send(:stage_detail_tab_path, :pipeline_name => "pipeline_name", :stage_name => "stage_name", :pipeline_counter => "10", :stage_counter => "2")).to eq("/pipelines/pipeline_name/10/stage_name/2")
    end

    it "should json url for stage" do
      expect(:get => "/pipelines/pipeline_name/10/stage_name/2.json").to route_to({:controller => "stages", :action => "overview", :pipeline_name => "pipeline_name", :stage_name => "stage_name", :pipeline_counter => "10", :stage_counter => "2", :format => "json"})
      expect(controller.send(:stage_detail_tab_path, :pipeline_name => "pipeline_name", :stage_name => "stage_name", :pipeline_counter => "10", :stage_counter => "2", :format => "json")).to eq("/pipelines/pipeline_name/10/stage_name/2.json")
    end

    it "should resolve 'rerun jobs' action" do
      expect(:post => "/pipelines/pipeline_name/10/stage_name/2/rerun-jobs").to route_to({:controller => "stages", :action => "rerun_jobs", :pipeline_name => "pipeline_name", :pipeline_counter => "10", :stage_name => "stage_name", :stage_counter => "2"})
      expect(controller.send(:rerun_jobs_path, {:pipeline_name => "pipeline_name", :stage_name => "stage_name", :pipeline_counter => 10, :stage_counter => 2})).to eq("/pipelines/pipeline_name/10/stage_name/2/rerun-jobs")
    end

    it "should generate stage details url for a tab" do
      expect(controller.send(:stage_detail_tab_path, :pipeline_name => "pipeline_name", :stage_name => "stage_name", :pipeline_counter => 10, :stage_counter => 2, :action => 'jobs')).to eq("/pipelines/pipeline_name/10/stage_name/2/jobs")
      expect(controller.send(:stage_detail_tab_path, :pipeline_name => "pipeline_name", :stage_name => "stage_name", :pipeline_counter => 10, :stage_counter => 2, :action => 'jobs', :format => 'json')).to eq("/pipelines/pipeline_name/10/stage_name/2/jobs.json")
      expect(controller.send(:stage_detail_tab_path, :pipeline_name => "pipeline_name", :stage_name => "stage_name", :pipeline_counter => 10, :stage_counter => 2, :action => 'overview')).to eq("/pipelines/pipeline_name/10/stage_name/2")
      expect(controller.send(:stage_detail_tab_path, :pipeline_name => "pipeline_name", :stage_name => "stage_name", :pipeline_counter => 10, :stage_counter => 2, :action => 'overview', :format => 'json')).to eq("/pipelines/pipeline_name/10/stage_name/2.json")
      expect(:get => "/pipelines/pipeline_name/10/stage_name/5/jobs").to route_to({:controller => "stages", :pipeline_name => "pipeline_name", :pipeline_counter => "10", :stage_name => "stage_name", :stage_counter => "5", :action => "jobs"})
    end

    it "should render action api/stages/index for :format xml" do
      stub_current_config
      stage_identifier = StageIdentifier.new("pipeline", 2, "stage", "3")

      allow(@status).to receive(:canContinue).and_return(true)
      expect(@stage_service).to receive(:findStageSummaryByIdentifier).with(stage_identifier, @user, @localized_result).and_return(@stage_summary_model)
      expect(@pipeline_history_service).to receive(:findPipelineInstance).with("pipeline", 2, 100, @user, @status).and_return(:pim)
      expect(@pipieline_lock_service).to receive(:lockedPipeline).with("pipeline").and_return(@pipeline_identifier)
      get :overview, :pipeline_name => "pipeline", :pipeline_counter => "2", :stage_name => "stage", :stage_counter => "3", :format => 'xml'

      expect(response).to redirect_to "/api/stages/#{@stage_summary_model.getId()}.xml"
    end

    it "should resolve piplines/stage-locator to the stage action" do
      expect(:get => "/pipelines/pipeline_name/10/stage_name/2.xml").to route_to({:controller => "stages", :action => 'overview', :pipeline_name => "pipeline_name", :stage_name => "stage_name", :pipeline_counter => "10", :stage_counter => "2", :format => "xml"})
      expect(controller.send(:stage_detail_tab_path, :pipeline_name => "pipeline_name", :stage_name => "stage_name", :pipeline_counter => "10", :stage_counter => "2", :format => "xml")).to eq("/pipelines/pipeline_name/10/stage_name/2.xml")
    end

    it "should load pipline instance " do
      stub_current_config
      now = org.joda.time.DateTime.new
      pim = PipelineHistoryMother.singlePipeline("pipline-name", PipelineHistoryMother.stagePerJob("stage-", [PipelineHistoryMother.job(JobState::Completed, JobResult::Cancelled, now.toDate()),
                                                                                                              PipelineHistoryMother.job(JobState::Completed, JobResult::Cancelled, now.plusDays(1).toDate())]))
      stage_summary_model=StageSummaryModel.new(stage_instance = StageMother.passedStageInstance("stage", "dev", "pipeline-name"), nil, JobDurationStrategy::ALWAYS_ZERO, nil)
      expect(@stage_service).to receive(:findStageSummaryByIdentifier).with(StageIdentifier.new("blah-pipeline-name", 12, "stage-0", "3"), @user, @localized_result).and_return(stage_summary_model)
      stage_instance.setPipelineId(100)
      expect(@pipeline_history_service).to receive(:findPipelineInstance).with("blah-pipeline-name", 12, 100, @user, @status).and_return(pim)
      allow(@pipeline_history_service).to receive(:validate).with("blah-pipeline-name", @user, @status)
      expect(@pipieline_lock_service).to receive(:lockedPipeline).with("blah-pipeline-name").and_return(@pipeline_identifier)
      allow(@status).to receive(:canContinue).and_return(true)
      expect(@localized_result).to receive(:isSuccessful).and_return(true)

      get :overview, :pipeline_name => "blah-pipeline-name", :pipeline_counter => "12", :stage_name => "stage-0", :stage_counter => "3", :format => 'xml'
      expect(assigns(:stage)).to eq stage_summary_model
      expect(assigns(:pipeline)).to eq pim
    end


    it "should render response code returned by the api result for pipeline" do
      expect(@status).to receive(:canContinue).and_return(false)
      allow(@status).to receive(:httpCode).and_return(401)
      allow(@status).to receive(:detailedMessage).and_return("no view permission")
      get :overview, :pipeline_name => "pipeline", :pipeline_counter => "2", :stage_name => "stage", :stage_counter => "3"
      expect(response.status).to eq 401
    end

    it "should assign locked instance" do
      stub_current_config
      expect(@stage_service).to receive(:findStageSummaryByIdentifier).with(StageIdentifier.new("pipeline", 2, "stage", "3"), @user, @localized_result).and_return(@stage_summary_model)
      expect(@pipeline_history_service).to receive(:findPipelineInstance).with("pipeline", 2, 100, @user, @status).and_return(:pim)
      expect(@pipieline_lock_service).to receive(:lockedPipeline).with("pipeline").and_return(@pipeline_identifier)
      allow(@status).to receive(:canContinue).and_return(true)

      get :overview, :pipeline_name => "pipeline", :pipeline_counter => "2", :stage_name => "stage", :stage_counter => "3"
      expect(assigns(:lockedPipeline)).to eq @pipeline_identifier
    end

    describe "overview tab" do
      it "should assign stage_history" do
        stub_current_config
        stage_identifier = StageIdentifier.new("pipeline", 2, "stage", "3")
        expect(@stage_service).to receive(:findStageHistoryPage).with(@stage_summary_model.getStage(), StagesController::STAGE_HISTORY_PAGE_SIZE).and_return(stage_history = stage_history_page(2))
        get :overview, :pipeline_name => "pipeline", :pipeline_counter => "2", :stage_name => "stage", :stage_counter => "3"
        expect(assigns(:stage_history_page)).to eq stage_history
      end

      it "should honour page number" do
        stub_current_config
        stage_identifier = StageIdentifier.new("pipeline", 2, "stage", "3")
        expect(@stage_service).to receive(:findStageHistoryPageByNumber).with("pipeline", "stage", 5, StagesController::STAGE_HISTORY_PAGE_SIZE).and_return(stage_history = stage_history_page(4))
        get :overview, :pipeline_name => "pipeline", :pipeline_counter => "2", :stage_name => "stage", :stage_counter => "3", "stage-history-page" => "5"
        expect(assigns(:stage_history_page)).to eq stage_history
      end
    end

    describe "jobs tab" do
      before :each do
        @security_service = double('security_service')
        allow(controller).to receive(:security_service).and_return(@security_service)
      end

      it "should get the job instance models from the stage" do
        stub_current_config
        job_instances = JobInstances.new([JobInstanceMother.assignedWithAgentId("job1", "123")])
        stage=StageMother.custom("pipeline", "stage", job_instances)
        stage.setPipelineId(1)
        stage_summary = StageSummaryModel.new(stage, Stages.new([stage]), JobDurationStrategy::ALWAYS_ZERO, nil)
        expect(@stage_service).to receive(:findStageSummaryByIdentifier).with(StageIdentifier.new("pipeline", 2, "stage", "3"), @user, @localized_result).and_return(stage_summary)
        expect(@job_presentation_service).to receive(:jobInstanceModelFor).with(job_instances).and_return(model = java.util.Arrays.asList([JobInstanceModel.new(nil, nil, nil)].to_java(JobInstanceModel)))
        expect(@security_service).to receive(:hasOperatePermissionForStage).with('pipeline', 'stage', @user.getUsername().to_s).and_return(true)
        get :jobs, :pipeline_name => "pipeline", :pipeline_counter => "2", :stage_name => "stage", :stage_counter => "3"
        expect(assigns(:jobs)).to eq model
      end

      it "should return true if user has operate permission on the stage" do
        stub_current_config
        job_instances = JobInstances.new([JobInstanceMother.assignedWithAgentId("job1", "123")])
        stage=StageMother.custom("pipeline", "stage", job_instances)
        stage.setPipelineId(1)
        stage_summary = StageSummaryModel.new(stage, Stages.new([stage]), JobDurationStrategy::ALWAYS_ZERO, nil)
        expect(@stage_service).to receive(:findStageSummaryByIdentifier).with(StageIdentifier.new("pipeline", 2, "stage", "3"), @user, @localized_result).and_return(stage_summary)
        expect(@job_presentation_service).to receive(:jobInstanceModelFor).with(job_instances).and_return(model = java.util.Arrays.asList([JobInstanceModel.new(nil, nil, nil)].to_java(JobInstanceModel)))
        expect(@security_service).to receive(:hasOperatePermissionForStage).with('pipeline', 'stage', @user.getUsername().to_s).and_return(true)
        get :jobs, :pipeline_name => "pipeline", :pipeline_counter => "2", :stage_name => "stage", :stage_counter => "3"
        expect(assigns(:jobs)).to eq model
        expect(assigns(:has_operate_permissions)).to eq true
      end

      it "should return false if user has no operate permission on the stage" do
        stub_current_config
        job_instances = JobInstances.new([JobInstanceMother.assignedWithAgentId("job1", "123")])
        stage=StageMother.custom("pipeline", "stage", job_instances)
        stage.setPipelineId(1)
        stage_summary = StageSummaryModel.new(stage, Stages.new([stage]), JobDurationStrategy::ALWAYS_ZERO, nil)
        expect(@stage_service).to receive(:findStageSummaryByIdentifier).with(StageIdentifier.new("pipeline", 2, "stage", "3"), @user, @localized_result).and_return(stage_summary)
        expect(@job_presentation_service).to receive(:jobInstanceModelFor).with(job_instances).and_return(model = java.util.Arrays.asList([JobInstanceModel.new(nil, nil, nil)].to_java(JobInstanceModel)))
        expect(@security_service).to receive(:hasOperatePermissionForStage).with('pipeline', 'stage', @user.getUsername().to_s).and_return(false)
        get :jobs, :pipeline_name => "pipeline", :pipeline_counter => "2", :stage_name => "stage", :stage_counter => "3"
        expect(assigns(:jobs)).to eq model
        expect(assigns(:has_operate_permissions)).to eq false
      end
    end

    describe "pipiline tab" do
      it "should get the dependency graph for the pipeline" do
        stub_current_config
        down1 = PipelineHistoryMother.singlePipeline("down1", StageInstanceModels.new)
        down2 = PipelineHistoryMother.singlePipeline("down2", StageInstanceModels.new)
        graph = PipelineDependencyGraphOld.new(@pim, PipelineInstanceModels.createPipelineInstanceModels([down1, down2]))
        expect(@pipeline_history_service).to receive(:pipelineDependencyGraph).with("pipeline", 99, @user, @status).and_return(graph)
        get :pipeline, :pipeline_name => "pipeline", :pipeline_counter => "99", :stage_name => "stage", :stage_counter => "3"
        expect(assigns(:graph)).to eq graph
      end

      it "should render op result if graph retrival fails" do
        stub_current_config
        allow(controller).to receive(:result_for_graph).and_return(result=double("result"))
        expect(@pipeline_history_service).to receive(:pipelineDependencyGraph).with("pipeline", 99, @user, result).and_return(:doesnt_matter)
        expect(result).to receive(:canContinue).and_return(false)
        allow(result).to receive(:detailedMessage).and_return("no view permission")
        allow(result).to receive(:httpCode).and_return(401)
        get :pipeline, :pipeline_name => "pipeline", :pipeline_counter => "99", :stage_name => "stage", :stage_counter => "3"
        expect(response.status).to eq 401
      end
    end

    describe "fbh tab" do

      before :each do
        stub_current_config
      end

      it "should assign information about unable to retrieve results if stage is still building" do
        stage = StageMother.scheduledStage("pipeline", 2, "stage", 1, "job1")
        stage.setPipelineId(1)
        stage_summary = StageSummaryModel.new(stage, Stages.new([stage]), JobDurationStrategy::ALWAYS_ZERO, nil)
        expect(@stage_service).to receive(:findStageSummaryByIdentifier).with(StageIdentifier.new("pipeline", 2, "stage", "3"), @user, @localized_result).and_return(stage_summary)
        get :tests, :pipeline_name => "pipeline", :pipeline_counter => "2", :stage_name => "stage", :stage_counter => "3"
        expect(assigns(:failing_tests_error_message)).to eq "Test Results will be generated when the stage completes."
      end

      it "should assign fbh when stage is completed" do
        stage_identifier = StageIdentifier.new("pipeline", 2, "stage", "3")
        expect(@shine_dao).to receive(:failedBuildHistoryForStage).with(stage_identifier, @subsection_result).and_return(failing_tests = double('StageTestResuls'))
        allow(failing_tests).to receive(:failingCounters).and_return([])
        expect(@go_config_service).to receive(:stageExists).with("pipeline", "stage").and_return(true)
        expect(@go_config_service).to receive(:stageHasTests).with("pipeline", "stage").and_return(true)
        get :tests, :pipeline_name => "pipeline", :pipeline_counter => "2", :stage_name => "stage", :stage_counter => "3"
        expect(assigns(:failing_tests)).to eq failing_tests
      end

      it "should assign fbh when stage does not exist in config" do
        stage_identifier = StageIdentifier.new("pipeline", 2, "stage", "3")
        expect(@shine_dao).to receive(:failedBuildHistoryForStage).with(stage_identifier, @subsection_result).and_return(:failing_tests)
        expect(@go_config_service).to receive(:stageExists).with("pipeline", "stage").and_return(false)
        get :tests, :pipeline_name => "pipeline", :pipeline_counter => "2", :stage_name => "stage", :stage_counter => "3"
        expect(assigns(:failing_tests)).to eq :failing_tests
      end

      it "should skip fetching failing tests if fragment already cached" do
        with_caching(true) do
          stage = StageMother.scheduledStage("pipeline", 2, "stage", 1, "job1")
          stage.setPipelineId(1)
          stage.calculateResult
          stage_summary = StageSummaryModel.new(stage, Stages.new([stage]), JobDurationStrategy::ALWAYS_ZERO, nil)
          expect(@stage_service).to receive(:findStageSummaryByIdentifier).with(StageIdentifier.new("pipeline", 2, "stage", "3"), @user, @localized_result).and_return(stage_summary)
          options = {:subkey => controller.view_cache_key.forFailedBuildHistoryStage(stage, "html")}
          view_cache_key = controller.view_cache_key.forFbhOfStagesUnderPipeline(stage.getIdentifier().pipelineIdentifier())
          ActionController::Base.cache_store.write(view_cache_key, "fbh", options)
          expect(@go_config_service).to receive(:stageHasTests).never
          get :tests, :pipeline_name => "pipeline", :pipeline_counter => "2", :stage_name => "stage", :stage_counter => "3", :format => "html"
          expect(assigns(:failing_tests_error_message)).to be_nil
          expect(assigns(:failing_tests)).to be_nil
        end
      end

    end
  end

  describe "history" do
    before do
      allow(@stage_service).to receive(:findStageHistoryPageByNumber).and_return(:stage_history_page)
    end

    it "should render without layout" do
      expect(@go_config_service).to receive(:getCurrentConfig).and_return(@cruise_config)
      pim = PipelineHistoryMother.singlePipeline("pipeline", StageInstanceModels.new)
      expect(@stage_service).to receive(:findStageHistoryPageByNumber).with('pipeline', 'stage', 3, 10).and_return(:stage_history_page)
      expect(@pipeline_history_service).to receive(:findPipelineInstance).with("pipeline", 10, @user, @status).and_return(pim)

      get :history, page: '3', pipeline_name: 'pipeline', stage_name: 'stage', pipeline_counter: 10, stage_counter: 5, tab: 'jobs'

      expect(response).to render_template(layout: nil)
    end

    it "should load stage history page" do
      expect(@go_config_service).to receive(:getCurrentConfig).and_return(@cruise_config)
      pim = PipelineHistoryMother.singlePipeline("pipeline", StageInstanceModels.new)
      expect(@stage_service).to receive(:findStageHistoryPageByNumber).with('pipeline', 'stage', 3, 10).and_return(:stage_history_page)
      expect(@pipeline_history_service).to receive(:findPipelineInstance).with("pipeline", 10, @user, @status).and_return(pim)
      get :history, :page => "3", :pipeline_name => 'pipeline', :stage_name => 'stage', :pipeline_counter => 10, :stage_counter => 5, :tab => 'jobs'
      expect(assigns(:stage_history_page)).to eq :stage_history_page
      expect(assigns(:pipeline)).to eq pim
    end

    it "should render stage history in response" do
      expect(@go_config_service).to receive(:getCurrentConfig).and_return(@cruise_config)
      pim = PipelineHistoryMother.singlePipeline("pipeline", StageInstanceModels.new)
      expect(@pipeline_history_service).to receive(:findPipelineInstance).with("pipeline", 10, @user, @status).and_return(pim)
      get :history, :page => "3", :pipeline_name => 'pipeline', :stage_name => 'stage', :pipeline_counter => 10, :stage_counter => 5, :tab => 'tests'

      assert_template "history"
    end

    it "should route to action" do
      expect(:get => "/history/stage/pipeline_name/10/stage_name/5?page=3").to route_to({:controller => "stages", :action => "history", :pipeline_name => "pipeline_name", :pipeline_counter => "10", :stage_name => "stage_name", :stage_counter => "5", :page => "3"})
      expect(controller.send(:stage_history_path, :pipeline_name => "pipeline_name", :pipeline_counter => "10", :stage_name => "stage_name", :stage_counter => "5", :page => "3")).to eq("/history/stage/pipeline_name/10/stage_name/5?page=3")
    end

    it "should generate the correct route" do
      expect(controller.send(:stage_history_path, {:pipeline_name => "pipeline_name", :pipeline_counter => 4, :stage_name => "stage_name", :stage_counter => 2, :page => "4"})).to eq("/history/stage/pipeline_name/4/stage_name/2?page=4")
    end

  end

  describe "config_change" do

    it "should route to action" do
      expect(:get => "/config_change/between/md5_value_2/and/md5_value_1").to route_to({:controller => "stages", :action => "config_change", :later_md5 => "md5_value_2", :earlier_md5 => "md5_value_1"})
      expect(controller.send(:config_change_path, :later_md5 => "md5_value_2", :earlier_md5 => "md5_value_1")).to eq("/config_change/between/md5_value_2/and/md5_value_1")
    end

    it "should generate the correct route" do
      expect(controller.send(:config_change_path, :later_md5 => "md5_value_2", :earlier_md5 => "md5_value_1")).to eq("/config_change/between/md5_value_2/and/md5_value_1")
    end

    it "should assign config changes for given md5" do
      result = HttpLocalizedOperationResult.new
      expect(@go_config_service).to receive(:configChangesFor).with("md5_value_2", "md5_value_1", result).and_return("changes_string")
      get :config_change, :later_md5 => "md5_value_2", :earlier_md5 => "md5_value_1"
      expect(assigns(:changes)).to eq "changes_string"
    end

    it "should assign error message if getting config changes for given md5 fails" do
      result = HttpLocalizedOperationResult.new
      expect(@go_config_service).to receive(:configChangesFor).with("md5_value_2", "md5_value_1", result)
      expect(result).to receive(:isSuccessful).and_return(false)
      allow(result).to receive(:httpCode).and_return(400)
      allow(result).to receive(:message).and_return("no config version found")
      get :config_change, :later_md5 => "md5_value_2", :earlier_md5 => "md5_value_1"
      expect(assigns(:config_change_error_message)).to eq "no config version found"
    end

    it "should assign message if config changes is nil because given md5 is the first revision in repo" do
      result = HttpLocalizedOperationResult.new
      expect(@go_config_service).to receive(:configChangesFor).with("md5_value_2", "md5_value_1", result).and_return(nil)
      expect(result).to receive(:isSuccessful).and_return(true)
      get :config_change, :later_md5 => "md5_value_2", :earlier_md5 => "md5_value_1"
      expect(assigns(:config_change_error_message)).to eq "This is the first entry in the config versioning. Please refer config tab to view complete configuration during this run."
    end
  end

  describe "stage_duration_chart" do

    before :each do
      stub_current_config
      @default_timezone = java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone("Asia/Colombo"))
    end

    after :each do
      java.util.TimeZone.setDefault(@default_timezone)
    end

    it "should load the duration of last 10 stages in seconds along with start-end dates and chart scale" do
      scheduledTime = org.joda.time.DateTime.new(2008, 2, 22, 10, 21, 23, 0, org.joda.time.DateTimeZone.forOffsetHoursMinutes(5, 30))
      stage1 = StageMother.createPassedStageWithFakeDuration("pipeline-name", 1, "stage", 1, "dev", scheduledTime, scheduledTime.plus_seconds(10))
      stage1.setPipelineId(100)
      stage2 = StageMother.createPassedStageWithFakeDuration("pipeline-name", 2, "stage", 1, "dev", scheduledTime, scheduledTime.plus_seconds(20))
      stage2.setPipelineId(101)
      stage3 = StageMother.createFailedStageWithFakeDuration("pipeline-name", 3, "stage", 1, "dev", scheduledTime, scheduledTime.plus_seconds(30))
      stage3.setPipelineId(102)
      stage_summary_model1 = StageSummaryModel.new(stage1, nil, JobDurationStrategy::ALWAYS_ZERO, nil)
      stage_summary_model2 = StageSummaryModel.new(stage2, nil, JobDurationStrategy::ALWAYS_ZERO, nil)
      stage_summary_model3 = StageSummaryModel.new(stage3, nil, JobDurationStrategy::ALWAYS_ZERO, nil)

      setup_stubs(stage_summary_model1, stage_summary_model2, stage_summary_model3)
      get :stats, :pipeline_name => "pipeline-name", :pipeline_counter => "1", :stage_name => "stage", :stage_counter => "1", :page_number => "2"

      expect(assigns(:chart_stage_duration_passed)).to eq ([{"link" => "/pipelines/pipeline-name/1/stage/1/jobs", "x" => 1, "key" => "1_10", "y" => 10}, {"link" => "/pipelines/pipeline-name/2/stage/1/jobs", "x" => 2, "key" => "2_20", "y" => 20}]).to_json
      expect(assigns(:chart_tooltip_data_passed)).to eq ({"1_10" => ["00:00:10", "22 Feb, 2008 at 10:21:23 [+0530]", "LABEL-1"], "2_20" => ["00:00:20", "22 Feb, 2008 at 10:21:23 [+0530]", "LABEL-2"]}).to_json
      expect(assigns(:chart_stage_duration_failed)).to eq ([{"link" => "/pipelines/pipeline-name/3/stage/1/jobs", "x" => 3, "key" => "3_30", "y" => 30}]).to_json
      expect(assigns(:chart_tooltip_data_failed)).to eq ({"3_30" => ["00:00:30", "22 Feb, 2008 at 10:21:23 [+0530]", "LABEL-3"]}).to_json
      expect(assigns(:chart_scale)).to eq "secs"
      expect(assigns(:pagination)).to eq Pagination.pageStartingAt(12, 200, 10)
      expect(assigns(:start_end_dates)).to eq ["22 Feb 2008", "22 Feb 2008"]
      expect(assigns(:no_chart_to_render)).to eq false
    end

    it "should load the duration of last 10 stages in minutes" do
      scheduledTime = org.joda.time.DateTime.new(2008, 2, 22, 10, 21, 23, 0, org.joda.time.DateTimeZone.forOffsetHoursMinutes(5, 30))
      stage1 = StageMother.createPassedStageWithFakeDuration("pipeline-name", 1, "stage", 1, "dev", scheduledTime, scheduledTime.plus_minutes(10))
      stage1.setPipelineId(100)
      stage2 = StageMother.createPassedStageWithFakeDuration("pipeline-name", 2, "stage", 1, "dev", scheduledTime, scheduledTime.plus_minutes(20))
      stage2.setPipelineId(101)
      stage_summary_model1 = StageSummaryModel.new(stage1, nil, JobDurationStrategy::ALWAYS_ZERO, nil)
      stage_summary_model2 = StageSummaryModel.new(stage2, nil, JobDurationStrategy::ALWAYS_ZERO, nil)

      setup_stubs(stage_summary_model1, stage_summary_model2)
      get :stats, :pipeline_name => "pipeline-name", :pipeline_counter => "1", :stage_name => "stage", :stage_counter => "1", :page_number => "2"

      expect(assigns(:chart_stage_duration_passed)).to eq ([{"link" => "/pipelines/pipeline-name/1/stage/1/jobs", "x" => 1, "key" => "1_600", "y" => 10.0}, {"link" => "/pipelines/pipeline-name/2/stage/1/jobs", "x" => 2, "key" => "2_1200", "y" => 20.0}]).to_json
      expect(assigns(:chart_tooltip_data_passed)).to eq ({"1_600" => ["00:10:00", "22 Feb, 2008 at 10:21:23 [+0530]", "LABEL-1"], "2_1200" => ["00:20:00", "22 Feb, 2008 at 10:21:23 [+0530]", "LABEL-2"]}).to_json
      expect(assigns(:chart_scale)).to eq "mins"
      expect(assigns(:start_end_dates)).to eq ["22 Feb 2008", "22 Feb 2008"]
    end

    it "should load data in ascending order of pipeline counters" do
      scheduledTime = org.joda.time.DateTime.new(2008, 2, 22, 10, 21, 23, 0, org.joda.time.DateTimeZone.forOffsetHoursMinutes(5, 30))
      stage1 = StageMother.createPassedStageWithFakeDuration("pipeline-name", 1, "stage", 1, "dev", scheduledTime, scheduledTime.plus_minutes(10))
      stage1.setPipelineId(100)
      stage2 = StageMother.createPassedStageWithFakeDuration("pipeline-name", 2, "stage", 1, "dev", scheduledTime, scheduledTime.plus_minutes(20))
      stage2.setPipelineId(101)
      stage3 = StageMother.createPassedStageWithFakeDuration("pipeline-name", 3, "stage", 1, "dev", scheduledTime, scheduledTime.plus_minutes(20))
      stage2.setPipelineId(102)
      stage_summary_model1 = StageSummaryModel.new(stage1, nil, JobDurationStrategy::ALWAYS_ZERO, nil)
      stage_summary_model2 = StageSummaryModel.new(stage2, nil, JobDurationStrategy::ALWAYS_ZERO, nil)
      stage_summary_model3 = StageSummaryModel.new(stage3, nil, JobDurationStrategy::ALWAYS_ZERO, nil)

      setup_stubs(stage_summary_model1, stage_summary_model3, stage_summary_model2)

      get :stats, :pipeline_name => "pipeline-name", :pipeline_counter => "1", :stage_name => "stage", :stage_counter => "1", :page_number => "2"

      expect(assigns(:chart_stage_duration_passed)).to eq ([{"link" => "/pipelines/pipeline-name/1/stage/1/jobs", "x" => 1, "key" => "1_600", "y" => 10.0},
                                                            {"link" => "/pipelines/pipeline-name/2/stage/1/jobs", "x" => 2, "key" => "2_1200", "y" => 20.0},
                                                            {"link" => "/pipelines/pipeline-name/3/stage/1/jobs", "x" => 3, "key" => "3_1200", "y" => 20.0}]).to_json
    end

    it "should load the correct pipeline label depending on stage run" do
      scheduledTime = org.joda.time.DateTime.new(2008, 2, 22, 10, 21, 23, 0, org.joda.time.DateTimeZone.forOffsetHoursMinutes(5, 30))
      stage1 = StageMother.createPassedStageWithFakeDuration("pipeline-name", 1, "stage", 1, "dev", scheduledTime, scheduledTime.plus_minutes(10))
      stage1.setPipelineId(100)
      stage2 = StageMother.createPassedStageWithFakeDuration("pipeline-name", 1, "stage", 2, "dev", scheduledTime, scheduledTime.plus_minutes(20))
      stage2.setPipelineId(101)
      stage_summary_model1 = StageSummaryModel.new(stage1, nil, JobDurationStrategy::ALWAYS_ZERO, nil)
      stage_summary_model2 = StageSummaryModel.new(stage2, nil, JobDurationStrategy::ALWAYS_ZERO, nil)

      setup_stubs(stage_summary_model1, stage_summary_model2)
      get :stats, :pipeline_name => "pipeline-name", :pipeline_counter => "1", :stage_name => "stage", :stage_counter => "1", :page_number => "2"

      expect(assigns(:chart_tooltip_data_passed)).to eq ({"1_600" => ["00:10:00", "22 Feb, 2008 at 10:21:23 [+0530]", "LABEL-1"], "1_1200" => ["00:20:00", "22 Feb, 2008 at 10:21:23 [+0530]", "LABEL-1 (run 2)"]}).to_json
    end

    it "should set the message when there is no stage history" do
      stage = StageMother.scheduledStage("pipeline-name", 1, "stage", 1, "dev")
      stage.setPipelineId(100)
      stage_summary_model = StageSummaryModel.new(stage, nil, JobDurationStrategy::ALWAYS_ZERO, nil)
      expect(@stage_service).to receive(:findStageSummaryByIdentifier).with(stage.getIdentifier(), @user, @localized_result).and_return(stage_summary_model)
      allow(@pipeline_history_service).to receive(:validate).with("pipeline-name", @user, @status)
      allow(@status).to receive(:canContinue).and_return(true)
      expect(@pipeline_history_service).to receive(:findPipelineInstance).with("pipeline-name", 1, 100, @user, @status).and_return(:pim)
      expect(@pipieline_lock_service).to receive(:lockedPipeline).with("pipeline-name").and_return("")
      expect(controller).to receive(:load_stage_history).with(no_args)
      expect(@stage_service).to receive(:findStageHistoryForChart).with("pipeline-name", "stage", 2, StagesController::STAGE_DURATION_RANGE, current_user).and_return(models = StageSummaryModels.new)

      get :stats, :pipeline_name => "pipeline-name", :pipeline_counter => "1", :stage_name => "stage", :stage_counter => "1", :page_number => "2"

      expect(assigns(:no_chart_to_render)).to eq true
    end

    it "should deal with stages when there are only failed stages" do
      scheduledTime = org.joda.time.DateTime.new(2008, 2, 22, 10, 21, 23, 0, org.joda.time.DateTimeZone.forOffsetHoursMinutes(5, 30))
      stage1 = StageMother.createFailedStageWithFakeDuration("pipeline-name", 1, "stage", 1, "dev", scheduledTime, scheduledTime.plus_minutes(10))
      stage1.setPipelineId(100)
      stage2 = StageMother.createFailedStageWithFakeDuration("pipeline-name", 2, "stage", 1, "dev", scheduledTime, scheduledTime.plus_minutes(20))
      stage2.setPipelineId(101)
      stage_summary_model1 = StageSummaryModel.new(stage1, nil, JobDurationStrategy::ALWAYS_ZERO, nil)
      stage_summary_model2 = StageSummaryModel.new(stage2, nil, JobDurationStrategy::ALWAYS_ZERO, nil)

      setup_stubs(stage_summary_model1, stage_summary_model2)
      get :stats, :pipeline_name => "pipeline-name", :pipeline_counter => "1", :stage_name => "stage", :stage_counter => "1", :page_number => "2"

      expect(assigns(:chart_stage_duration_passed)).to eq [].to_json
      expect(assigns(:chart_tooltip_data_passed)).to eq ({}).to_json
      expect(assigns(:chart_stage_duration_failed)).to eq ([{"link" => "/pipelines/pipeline-name/1/stage/1/jobs", "x" => 1, "key" => "1_600", "y" => 10.0}, {"link" => "/pipelines/pipeline-name/2/stage/1/jobs", "x" => 2, "key" => "2_1200", "y" => 20.0}]).to_json
      expect(assigns(:chart_tooltip_data_failed)).to eq ({"1_600" => ["00:10:00", "22 Feb, 2008 at 10:21:23 [+0530]", "LABEL-1"], "2_1200" => ["00:20:00", "22 Feb, 2008 at 10:21:23 [+0530]", "LABEL-2"]}).to_json
      expect(assigns(:chart_scale)).to eq "mins"
      expect(assigns(:start_end_dates)).to eq ["22 Feb 2008", "22 Feb 2008"]
    end

    def setup_stubs(*stage_summary_models)
      models = StageSummaryModels.new
      models.addAll(stage_summary_models)
      models.setPagination(Pagination.pageStartingAt(12, 200, 10))
      expect(@pipieline_lock_service).to receive(:lockedPipeline).with("pipeline-name").and_return("")
      stage_iden = stage_summary_models[0].getStage().getIdentifier()
      expect(@stage_service).to receive(:findStageSummaryByIdentifier).with(stage_iden, @user, @localized_result).and_return(stage_summary_models[0])
      allow(@pipeline_history_service).to receive(:validate).with("pipeline-name", @user, @status)
      expect(@pipeline_history_service).to receive(:findPipelineInstance).with("pipeline-name", 1, 100, @user, @status).and_return(:pim)
      allow(@status).to receive(:canContinue).and_return(true)
      expect(controller).to receive(:load_stage_history).with(no_args)
      expect(@stage_service).to receive(:findStageHistoryForChart).with(stage_iden.getPipelineName(), stage_iden.getStageName(), 2, StagesController::STAGE_DURATION_RANGE, current_user).and_return(models)
    end
  end

  describe "config_tab" do
    before do
      scheduledTime = org.joda.time.DateTime.new(2008, 2, 22, 10, 21, 23, 0, org.joda.time.DateTimeZone.forOffsetHoursMinutes(5, 30))
      stage = StageMother.createPassedStageWithFakeDuration("pipeline-name", 1, "stage", 1, "dev", scheduledTime, scheduledTime.plus_minutes(10))
      stage.setPipelineId(100)
      stage.setConfigVersion("some-config-md5")
      @stage_summary_model = StageSummaryModel.new(stage, nil, JobDurationStrategy::ALWAYS_ZERO, nil)
      setup_stubs(@stage_summary_model)
      stub_current_config
    end

    it "should get config for the particular stage instance" do
      get :stage_config, :pipeline_name => "pipeline-name", :pipeline_counter => "1", :stage_name => "stage", :stage_counter => "1"

      expect(assigns(:stage)).to eq @stage_summary_model
      expect(assigns(:ran_with_config_revision)).to eq :some_cruise_config_revision
    end

    def setup_stubs(stage_summary_model)
      expect(@pipieline_lock_service).to receive(:lockedPipeline).with("pipeline-name").and_return("")
      expect(@stage_service).to receive(:findStageSummaryByIdentifier).with(stage_summary_model.getStage().getIdentifier(), @user, @localized_result).and_return(stage_summary_model)
      allow(@pipeline_history_service).to receive(:validate).with("pipeline-name", @user, @status)
      expect(@pipeline_history_service).to receive(:findPipelineInstance).with("pipeline-name", 1, 100, @user, @status).and_return(:pim)
      allow(@status).to receive(:canContinue).and_return(true)
      expect(controller).to receive(:load_stage_history).with(no_args)
      expect(@go_config_service).to receive(:getConfigAtVersion).with("some-config-md5").and_return(:some_cruise_config_revision)
    end
  end

  describe "stage_settings_link" do
    before :each do
      expect(@pipeline_history_service).to receive(:validate).and_return(nil)
      @security_service = double('stage service')
      allow(controller).to receive(:security_service).and_return(@security_service)
      allow(controller).to receive(:can_continue).and_return(nil)
      allow(controller).to receive(:load_stage_history).and_return(nil)
      allow(controller).to receive(:load_current_config_version).and_return(nil)
      allow(@go_config_service).to receive(:isPipelineEditable).and_return(true)
      expect(@go_config_service).to receive(:findGroupNameByPipeline).and_return('group')
    end
    it 'should return false for normal users' do
      login_as_user

      expect(@security_service).to receive(:isUserAdminOfGroup).with(anything, 'group').and_return(false)

      get :overview, pipeline_name: "pipeline", pipeline_counter: "2", stage_name: "stage", stage_counter: "3"

      expect(controller.instance_variable_get(:@can_user_view_settings)).to eq(false)
    end

    it 'should return true for admin users' do
      login_as_admin

      expect(@security_service).to receive(:isUserAdminOfGroup).with(anything, 'group').and_return(true)

      get :overview, pipeline_name: "pipeline", pipeline_counter: "2", stage_name: "stage", stage_counter: "3"

      expect(controller.instance_variable_get(:@can_user_view_settings)).to eq(true)
    end

    it 'should return false for admin users when pipeline is not editable from UI' do
      login_as_admin

      expect(@go_config_service).to receive(:isPipelineEditable).and_return(false)
      expect(@security_service).to receive(:isUserAdminOfGroup).with(anything, 'group').and_return(true)

      get :overview, pipeline_name: "pipeline", pipeline_counter: "2", stage_name: "stage", stage_counter: "3"

      expect(controller.instance_variable_get(:@can_user_view_settings)).to eq(false)
    end
  end

  describe 'redirect_to_first_stage' do
    it 'should redirect to first stage of the pipeline instance' do
      pipeline_name = "pipeline_name"
      stage_name = "stage_name"
      pim = PipelineHistoryMother.pipelineHistoryItemWithOneStage(pipeline_name, stage_name, java.util.Date.new)
      expect(@pipeline_history_service).to receive(:findPipelineInstance).with(pipeline_name, 1, @user, @status).and_return(pim)

      get :redirect_to_first_stage, pipeline_name: 'pipeline_name', pipeline_counter: 1

      expect(response.status).to eq(302)
      expect(response).to redirect_to("/pipelines/#{pipeline_name}/1/#{stage_name}/1")
    end

    it 'should render not found page when pipeline instance for the provided pipeline name is not present' do
      pipeline_name = "pipeline_name"
      expect(@pipeline_history_service).to receive(:findPipelineInstance).with(pipeline_name, 1, @user, @status).and_return(nil)

      get :redirect_to_first_stage, pipeline_name: 'pipeline_name', pipeline_counter: 1

      expect(response.status).to eq(404)
    end
  end
end
