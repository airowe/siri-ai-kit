# Throwaway spike: builds SimulatorSiriSpike.xcodeproj, the example app plus a UI test target that runs on the
# Simulator (the real evals target imports SiriEvaluations, which the Simulator SDK lacks).
# Run: ruby Example/spikes/simulator-siri/generate-project.rb
require 'xcodeproj'

SPIKE_DIR = __dir__
PROJECT_PATH = File.join(SPIKE_DIR, 'SimulatorSiriSpike.xcodeproj')
APP = 'SiriAIKitExample'
TESTS = 'SimulatorSiriSpikeTests'
DEPLOYMENT_TARGET = '27.3'
BUNDLE_ID = 'com.example.siriaikit'

project = Xcodeproj::Project.new(PROJECT_PATH)
package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
package.relative_path = '../../..'
project.root_object.package_references << package

def add_sources(project, target, folder)
  group = project.main_group.new_group(File.basename(folder), folder)
  Dir[File.join(SPIKE_DIR, folder, '*.swift')].sort.each do |file|
    target.add_file_references([group.new_file(File.basename(file))])
  end
end

def link_product(project, target, package, name)
  dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dependency.package = package
  dependency.product_name = name
  target.package_product_dependencies << dependency
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dependency
  target.frameworks_build_phase.files << build_file
end

app = project.new_target(:application, APP, :ios, DEPLOYMENT_TARGET)
add_sources(project, app, "../../#{APP}")
link_product(project, app, package, 'SiriAIKit')

tests = project.new_target(:ui_test_bundle, TESTS, :ios, DEPLOYMENT_TARGET)
tests.add_dependency(app)
add_sources(project, tests, TESTS)
link_product(project, tests, package, 'SiriAIKit')

shared = {
  'SWIFT_VERSION' => '6.0',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'CODE_SIGN_STYLE' => 'Automatic',
  'IPHONEOS_DEPLOYMENT_TARGET' => DEPLOYMENT_TARGET,
  'TARGETED_DEVICE_FAMILY' => '1',
}
app.build_configurations.each do |config|
  config.build_settings.merge!(shared).merge!(
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'PRODUCT_BUNDLE_IDENTIFIER' => BUNDLE_ID,
    'INFOPLIST_KEY_CFBundleDisplayName' => 'SiriAIKit Example',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
    'MARKETING_VERSION' => '1.0',
    'CURRENT_PROJECT_VERSION' => '1',
  )
end
tests.build_configurations.each do |config|
  config.build_settings.merge!(shared).merge!(
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'PRODUCT_BUNDLE_IDENTIFIER' => "#{BUNDLE_ID}.simspike",
    'TEST_TARGET_NAME' => APP,
  )
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(tests)
scheme.save_as(PROJECT_PATH, TESTS, true)
puts "Generated #{File.basename(PROJECT_PATH)}"
