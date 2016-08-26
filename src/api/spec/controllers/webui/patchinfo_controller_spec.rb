require 'rails_helper'
# WARNING: If you change tests make sure you uncomment this line
# and start a test backend. Some of the Patchinfo methods
# require real backend answers for projects/packages.
# CONFIG['global_write_through'] = true

RSpec.describe Webui::PatchinfoController, vcr: true do
  let(:user) { create(:user, login: 'macario') }
  let(:other_user) { create(:confirmed_user, login: 'gilberto')}
  let(:other_package) { create(:package_with_file, project: user.home_project, name: 'other_package') }
  let(:patchinfo_package) do
    Patchinfo.new.create_patchinfo(user.home_project_name, nil) unless user.home_project.exists_package? 'patchinfo'
    Package.get_by_project_and_name(user.home_project_name, 'patchinfo', use_source: false)
  end

  def do_proper_post_save
    post :save, project: user.home_project_name,
                package: patchinfo_package.name,
                summary: 'long enough summary is ok',
                description: 'long enough description is also ok' * 5,
                issueid: [769484],
                issuetracker: ['bgo'],
                issuesum: [],
                issueurl: ['https://bugzilla.gnome.org/show_bug.cgi?id=769484'],
                category: 'recommended',
                rating: 'low',
                packager: user.login
  end

  let(:fake_build_results) do
    Buildresult.new(
      '<resultlist state="2b71f05ecb8742e3cd7f6066a5097c72">
        <result project="home:macario" repository="fake_repo" arch="i586" code="unknown" state="unknown" dirty="true">
         <binarylist>
            <binary filename="fake_binary_001"/>
            <binary filename="fake_binary_002"/>
            <binary filename="updateinfo.xml"/>
            <binary filename="rpmlint.log"/>
          </binarylist>
        </result>
      </resultlist>')
  end

  let(:fake_patchinfo_with_binaries) do
    Patchinfo.new(
      '<patchinfo>
        <category>recommended</category>
        <rating>low</rating>
        <packager>macario</packager>
        <summary/>
        <description/>
        <binary>fake_binary_001</binary>
      </patchinfo>')
  end

  after do
    Package.destroy_all
  end

  describe 'POST #new_patchinfo' do
    before do
      other_user
      login user
    end

    context 'without permission to create the patchinfo package' do
      before do
        post :new_patchinfo, project: other_user.home_project
      end

      it { expect(response).to redirect_to(project_show_path(other_user.home_project)) }
      it { expect(flash[:error]).to eq "No permission to create packages" }
    end

    context 'when it fails to create the patchinfo package' do
      before do
        Patchinfo.any_instance.stubs(:create_patchinfo).returns(false)
        post :new_patchinfo, project: user.home_project
      end

      it { expect(response).to redirect_to(project_show_path(user.home_project)) }
      it { expect(flash[:error]).to eq "Error creating patchinfo" }
    end

    context 'when the patchinfo package file is not found' do
      before do
        Package.any_instance.stubs(:patchinfo).returns(nil)
        post :new_patchinfo, project: user.home_project
      end

      it { expect(response).to redirect_to(package_show_path(project: user.home_project, package: 'patchinfo')) }
      it { expect(flash[:error]).to eq("Patchinfo not found for #{user.home_project.name}") }
    end

    context 'when is successfull creating the patchinfo package' do
      before do
        Buildresult.stubs(:find).returns(fake_build_results)
        Package.any_instance.stubs(:patchinfo).returns(fake_patchinfo_with_binaries)
        post :new_patchinfo, project: user.home_project
      end

      it { expect(response).to have_http_status(:success) }
      it { expect(assigns(:binarylist)).to match_array(["fake_binary_002"]) }
      it { expect(assigns(:binaries)).to match_array(["fake_binary_001"]) }
      it { expect(assigns(:packager)).to eq(user.login) }
      it { expect(assigns(:file)).not_to be_nil }
    end
  end

  describe 'POST #updatepatchinfo' do
    before do
      login user
    end

    context 'without a valid patchinfo' do
      before do
        post :updatepatchinfo, project: user.home_project_name, package: other_package.name
      end

      it { expect(flash[:error]).to eq("Patchinfo not found for #{user.home_project_name}") }
      it { expect(response).to redirect_to(package_show_path(project: user.home_project_name, package: other_package.name)) }
    end

    context 'with a valid patchinfo' do
      it 'updates and redirects to edit_patchinfo' do
        Patchinfo.any_instance.expects(:cmd_update_patchinfo).with(user.home_project_name, patchinfo_package.name)
        post :updatepatchinfo, project: user.home_project_name, package: patchinfo_package.name
        expect(response).to redirect_to(action: 'edit_patchinfo', project: user.home_project_name, package: patchinfo_package.name)
      end
    end
  end

  describe 'GET #edit_patchinfo' do
    before do
      login user
      post :edit_patchinfo, project: user.home_project_name, package: patchinfo_package.name
    end

    it { expect(response).to have_http_status(:success) }
    it { expect(assigns(:binaries)).to be_a Array }
    it { expect(assigns(:tracker)).to eq(::Configuration.default_tracker) }
  end

  describe 'GET #show' do
    before do
      login user
      get :show, project: user.home_project_name, package: patchinfo_package.name
    end

    it { expect(response).to have_http_status(:success) }
    it { expect(assigns(:binaries)).to be_a Array }
    it { expect(assigns(:pkg_names)).to be_empty }
    it { expect(assigns(:packager)).to eq(user) }
  end

  describe 'POST #save' do
    before do
      login user
    end

    # This validation is performed at controller level and outside the model
    context 'with a short summary' do
      before do
        post :save, project: user.home_project_name, package: patchinfo_package.name, summary: 'short', description: 'long description ' * 10
      end

      it { expect(flash[:error]).to eq("|| Summary is too short (should have more than 10 signs)") }
      it { expect(response).to have_http_status(:success) }
    end

    # This validation is performed at controller level and outside the model
    context 'with a short description' do
      before do
        post :save, project: user.home_project_name, package: patchinfo_package.name, summary: 'long enough summary is ok', description: 'short'
      end

      it { expect(flash[:error]).to eq(" || Description is too short (should have more than 50 signs and longer than summary)") }
      it { expect(response).to have_http_status(:success) }
    end

    context 'with an unknown issue tracker' do
      before do
        post :save, project: user.home_project_name,
                    package: patchinfo_package.name,
                    summary: 'long enough summary is ok',
                    description: 'long enough description is also ok' * 5,
                    issueid: [769484],
                    issuetracker: ['NonExistingTracker'],
                    issuesum: [],
                    issueurl: ['https://bugzilla.gnome.org/show_bug.cgi?id=769484']
      end

      it { expect(flash[:error]).to eq("Unknown Issue tracker NonExistingTracker") }
      it { expect(response).to have_http_status(:success) }
    end

    context "when the patchinfo's xml is invalid" do
      before do
        post :save, project: user.home_project_name,
                    package: patchinfo_package.name,
                    summary: 'long enough summary is ok',
                    description: 'long enough description is also ok' * 5,
                    issueid: [769484],
                    issuetracker: ['bgo'],
                    issuesum: [],
                    issueurl: ['https://bugzilla.gnome.org/show_bug.cgi?id=769484']
      end

      it { expect(flash[:error]).to start_with("patchinfo is invalid: ") }
      it { expect(response).to have_http_status(:success) }
    end

    context "when the patchinfo's xml is valid" do
      before do
        post :new_patchinfo, project: user.home_project # this creates the patchinfo without summary and description
        do_proper_post_save
        @patchinfo = Package.get_by_project_and_name(user.home_project_name, 'patchinfo', use_source: false).patchinfo.to_hash
      end

      it { expect(@patchinfo['summary']).to eq('long enough summary is ok') }
      it { expect(@patchinfo['description']).to eq('long enough description is also ok' * 5) }
      it { expect(flash[:notice]).to eq("Successfully edited #{patchinfo_package.name}") }
      it { expect(response).to redirect_to(action: 'show', project: user.home_project_name, package: patchinfo_package.name) }
    end

    context "without permission to edit the patchinfo-file" do
      before do
        patchinfo_package
        Suse::Backend.stubs(:put).raises(ActiveXML::Transport::ForbiddenError)
        do_proper_post_save
      end

      it { expect(flash[:error]).to eq('No permission to edit the patchinfo-file.') }
      it { expect(response).to redirect_to(action: 'show', project: user.home_project_name, package: patchinfo_package.name) }
    end

    context "putting the file is taking so long that will raise a timeout" do
      before do
        patchinfo_package
        Suse::Backend.stubs(:put).raises(Timeout::Error)
        do_proper_post_save
      end

      it { expect(flash[:error]).to eq('Timeout when saving file. Please try again.') }
      it { expect(response).to redirect_to(action: 'show', project: user.home_project_name, package: patchinfo_package.name) }
    end
  end

  describe 'GET #remove' do
    before do
      login user
    end

    context 'if package can be removed' do
      before do
        post :remove, project: user.home_project_name, package: patchinfo_package.name
      end

      it { expect(flash[:notice]).to eq("Patchinfo was successfully removed.") }
      it { expect(response).to redirect_to(project_show_path(user.home_project)) }
    end

    context "if package can't be removed" do
      before do
        Package.any_instance.stubs(:check_weak_dependencies?).returns(false)
        post :remove, project: user.home_project_name, package: patchinfo_package.name
      end

      it { expect(flash[:notice]).to eq("Patchinfo can't be removed: ") }
      it { expect(response).to redirect_to(patchinfo_show_path(package: patchinfo_package, project: user.home_project)) }
    end
  end

  describe 'GET #new_tracker' do
    before do
      login user
    end

    context 'if issues are ok' do
      before do
        get :new_tracker, project: user.home_project_name, package: patchinfo_package.name, issues: ['bgo#132412']
      end

      it do
        expect(JSON.parse(response.body)).to eq({
                                                  "error"  => '',
                                                  "issues" => [['bgo', '132412', 'https://bugzilla.gnome.org/show_bug.cgi?id=132412', '']]
                                                })
      end
      it { expect(response).to have_http_status(:success) }
    end

    context "if issues are wrongly formatted" do
      before do
        get :new_tracker, project: user.home_project_name, package: patchinfo_package.name, issues: ['hell#666']
      end

      it { expect(JSON.parse(response.body)).to eq({"error" => "hell is not a valid tracker.\n", "issues" => []}) }
      it { expect(response).to have_http_status(:success) }
    end
  end
end