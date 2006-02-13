#!/usr/local/bin/perl -w

use strict;
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use HTML::Template;
use Monitor;
use XML::Twig;

my $q = new CGI;

print $q->header( -type => 'text/html' );
my $tmpl = HTML::Template->new( filename => 'templates/pipeline_list.tmpl',
                                die_on_bad_params => 1,
                              );

my $repository_root = $q->param("repository_root") || die "pass a repository root";

my $pipeline_root = "$repository_root/Workflow/pipeline";
my $errors_found  = 0;
my $error_msgs = [];
my %pipelines;
my $pipeline_count = 0;

## make sure the directory exists
if (! -e $pipeline_root) {
    &record_error("$pipeline_root not found.  enter a repository root that contains a Workflow directory.");
    &print_template();
}

my $rdh;
if (! opendir $rdh, "$pipeline_root" ) {
    &record_error("can't open pipeline root directory: $!");
    &print_template();
}

## make sure it has a 'workflow' directory
if (! -d "$repository_root/workflow" ) {
    &record_error("directory $repository_root/workflow not found");
}

## make sure it has a 'workflow/lock_files' directory
if (! -d "$repository_root/workflow/lock_files" ) {
    &record_error("directory $repository_root/workflow/lock_files not found");
}

## quit and throw the template if there were errors.
if ( scalar @{$error_msgs} ) {
    &print_template();
}

foreach my $pipeline_id ( readdir $rdh ) {
    next unless ( $pipeline_id =~ /^\d+$/ );
    $pipeline_count++;

    my $state = 'unknown';
    my $last_mod = 'unknown';
    my $start_time = 'unknown';
    my $end_time = 'unknown';
    my $run_time = 'unknown';
    my $pipeline_user = 'unknown';
    my $component_count = 0;
    my $component_aref = [];
    my $component_label = ' components';
    my $pipeline_file = "$repository_root/Workflow/pipeline/$pipeline_id/pipeline.xml";  ## may be modified below
    my $is_instance = 0;
    my $view_link = "./view_workflow_pipeline.cgi?instance=$pipeline_file";
    my $edit_link = "./show_pipeline.cgi?xmltemplate=$pipeline_file&amp;edit=1";
    my $archive_link = "./archive_pipeline_form.cgi?repository_root=$repository_root&amp;pipeline_id=$pipeline_id";
    my $links_enabled = 1;
    
    ## see if this pipeline is locked (usually for maintenance such as deleting or archiving.)
    my $lock_file = "$repository_root/workflow/lock_files/pipeline.$pipeline_id.lock";
    if ( -e $lock_file ) {
        ## get the state from the lock file, currently the only contents
        open (my $lockfh, "<$lock_file") || die "can't read lock file\n";
        $state = readline $lockfh;
        chomp $state;
    
        $run_time = '';
        $links_enabled = 0;
    
    } else {

        ## if the pipeline.xml.instance exists, just process it
        if (-e "$pipeline_file.instance" ) {
            $pipeline_file .= '.instance';
            $is_instance = 1;

        ## elsif only the pipeline.xml exists, we can do less
        } elsif ( -e "$repository_root/Workflow/pipeline/$pipeline_id/pipeline.xml" ) {
            $is_instance = 0;

        ## else don't have enough info to go one, skip it.
        } else {
            next;
        }

        my $twig = new XML::Twig;
        $twig->parsefile($pipeline_file);

        my $commandSetRoot = $twig->root;
        my $commandSet = $commandSetRoot->first_child('commandSet');

        next if (! $commandSet );

        if ( $commandSet->first_child('state') ) {
            $state  = $commandSet->first_child('state')->text();
        }

        ($start_time, $end_time, $run_time) = &time_info( $commandSet );

        my $filestat = stat($pipeline_file);
        $pipeline_user = getpwuid($filestat->uid);
        #$last_mod = time - $filestat->mtime;
        #$last_mod = strftime( "%H hr %M min %S sec", reverse split(/:/, DateCalc("today", ParseDate(DateCalc("now", "- ${last_mod} seconds")) ) ));
        #$last_mod = localtime( $filestat->mtime );
        $last_mod = $filestat->mtime;

        ## this is done as a new twig parse since elements can be nested
        ## at any level.
        my %components = &component_count_hash( $pipeline_file );

        foreach my $component (sort keys %components) {
            $component_count += $components{$component};
            push @$component_aref, { name => $component, count => $components{$component} };
        }

        ## reformat component_count to include a label
        if ($component_count == 1) {
            $component_label = ' component';
        }
    }
    
    $pipelines{$pipeline_id} = { 
                        pipeline_id     => $pipeline_id,
                        state           => $state,
                        last_mod        => $last_mod,
                        run_time        => $run_time,
                        pipeline_user   => $pipeline_user,
                        components      => \@$component_aref,
                        component_count => $component_count,
                        component_label => $component_label,
                        view_link       => $view_link,
                        edit_link       => $edit_link,
                        archive_link    => $archive_link,
                        links_enabled    => $links_enabled,
                      };
}

## sort the pipelines
my @pipelines_sorted;

for my $pipeline ( sort { $pipelines{$b}{last_mod} cmp $pipelines{$a}{last_mod} } keys %pipelines ) {
    $pipelines{$pipeline}{last_mod} = localtime( $pipelines{$pipeline}{last_mod} );
    push @pipelines_sorted, $pipelines{$pipeline};
}

## populate the template
&print_template();

sub print_template {

    ## populate the template with the values that will always be passed.
    $tmpl->param( ERRORS_FOUND    => $errors_found );
    $tmpl->param( REPOSITORY_ROOT => $repository_root );
    $tmpl->param( ERROR_MSGS      => $error_msgs );
    $tmpl->param( PIPELINES       => \@pipelines_sorted );
    $tmpl->param( PIPELINE_COUNT  => $pipeline_count );

    ## print the template
    print $tmpl->output();
    exit;
}

sub record_error {
    my $error_string = shift;
    
    $errors_found++;
    push @$error_msgs, { msg => $error_string };
}
