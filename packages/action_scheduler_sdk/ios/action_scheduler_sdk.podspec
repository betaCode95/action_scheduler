Pod::Spec.new do |s|
  s.name             = 'action_scheduler_sdk'
  s.version          = '1.0.0'
  s.summary          = 'Action Scheduler SDK - Background task scheduling for Flutter'
  s.description      = 'A cross-platform Flutter SDK for scheduling and running local tasks with flexible recurrence rules.'
  s.homepage         = 'https://github.com/betaCode95/action_scheduler'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Action Scheduler' => 'dev@actionscheduler.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
