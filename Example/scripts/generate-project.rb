# Generates SyrupAIKitExample.xcodeproj: the example app, its Siri evaluations target, and a shared scheme.
# The project is committed; run this to regenerate it after adding files.
require 'xcodeproj'

EXAMPLE_DIR = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(EXAMPLE_DIR, 'SyrupAIKitExample.xcodeproj')
APP = 'SyrupAIKitExample'
EVALS = 'SyrupAIKitExampleEvals'
DEPLOYMENT_TARGET = '27.3'
BUNDLE_ID = 'com.example.syrupaikit'

project = Xcodeproj::Project.new(PROJECT_PATH)
package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
package.relative_path = '..'
project.root_object.package_references << package

def add_sources(project, targets, folder)
  group = project.main_group.new_group(folder, folder)
  Dir[File.join(EXAMPLE_DIR, folder, '*.swift')].sort.each do |file|
    reference = group.new_file(File.basename(file))
    Array(targets).each { |target| target.add_file_references([reference]) }
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
add_sources(project, app, APP)
link_product(project, app, package, 'SyrupAIKit')

evals = project.new_target(:ui_test_bundle, EVALS, :ios, DEPLOYMENT_TARGET)
evals.add_dependency(app)
add_sources(project, evals, EVALS)
link_product(project, evals, package, 'SyrupAIEvalKit')
# Code both targets need to agree on, such as the switches the evaluations launch the app with.
add_sources(project, [app, evals], 'Shared')

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
    'INFOPLIST_KEY_CFBundleDisplayName' => 'SyrupAIKit Example',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
    'MARKETING_VERSION' => '1.0',
    'CURRENT_PROJECT_VERSION' => '1',
  )
end
evals.build_configurations.each do |config|
  config.build_settings.merge!(shared).merge!(
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'PRODUCT_BUNDLE_IDENTIFIER' => "#{BUNDLE_ID}.evals",
    'TEST_TARGET_NAME' => APP,
  )
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(evals)
scheme.save_as(PROJECT_PATH, EVALS, true)
puts "Generated #{File.basename(PROJECT_PATH)} with #{APP}, #{EVALS} and the #{EVALS} scheme"
