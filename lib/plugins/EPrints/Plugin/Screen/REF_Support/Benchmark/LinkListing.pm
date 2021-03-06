package EPrints::Plugin::Screen::REF_Support::Benchmark::LinkListing;

# Adds a button on Workflow::View to allow people to return to the Listing screen

use EPrints::Plugin::Screen::REF_Support;
@ISA = ( 'EPrints::Plugin::Screen::REF_Support' );

use strict;

sub new
{
	my( $class, %params ) = @_;

	my $self = $class->SUPER::new(%params);

	$self->{actions} = [qw/ link /];

	$self->{appears} = [
		{
			place => "dataobj_view_actions",
			dataset => "ref_support_benchmark",
			action => "link",
			position => 10,
		},
	];

	return $self;
}

sub can_be_viewed
{
        my( $self ) = @_;

        if( defined $self->{processor}->{dataset} )
        {
                return 0 if( $self->{processor}->{dataset}->id ne 'ref_support_benchmark' );
        }

	return $self->allow( 'ref_support_benchmark/create_new' );
}

sub allow_link
{
	my ( $self ) = @_;

	return $self->can_be_viewed();
}

sub action_link
{
	my( $self ) = @_;

	$self->{processor}->{redirect} = $self->{session}->config( 'userhome' )."?screen=Listing&dataset=ref_support_benchmark";
}	

sub render { return shift->{session}->make_doc_fragment }

1;
