use Module::Build;
# See perldoc Module::Build for details of how this works

Module::Build->new
    ( module_name     => 'Mail::Log::Parse',
      license         => 'perl',
      dist_author     => 'Daniel Staal - <DStaal@usa.net>',
      dist_abstract   => 'Parse and return info in maillogs.',
      create_readme   => 1,
      create_makefile_pl => 'passthrough',
      requires        => 	{
							'perl'		=> '5.6.1',
							'Scalar::Util'	=> 0,
							'Time::Local'	=> 0,
							'IO::File'		=> 0,
							'File::Basename'=> 0,
							'Mail::Log::Exceptions' => 0,
							},
      build_requires  =>	{
							'Module::Build'	=> 0, 
							'Test::Warn'		=> 0,
							'Test::Exception' => 0,
							},
      recommends      =>	{
							'IO::Uncompress::AnyUncompress' => 0,
							'File::Temp'	=> '0.17',
							},

    )->create_build_script;
