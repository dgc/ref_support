package EPrints::Plugin::Screen::REF_Support::Listing;

use EPrints::Plugin::Screen::REF_Support;
use EPrints::Plugin::Screen::AbstractSearch;
@ISA = qw(
	EPrints::Plugin::Screen::AbstractSearch
	EPrints::Plugin::Screen::REF_Support
);

sub new
{
	my( $class, %params ) = @_;

	my $self = $class->EPrints::Plugin::Screen::REF_Support::new( %params );

	push @{$self->{actions}}, qw/ update search newsearch search_authored search_deposited search_authored_all search_deposited_all select unselect sync /;

	$self->{appears} = [
# replaced by REF::Overview:
#		{
#			place => "key_tools",
#			position => 1000,
#		},
                {
                        place => "ref_support_listing_user_actions",
                        position => 300
                },
	];

	$self->{stime} = time();

	return $self;
}

sub can_be_viewed 
{
        my( $self ) = @_;

        my $rc = $self->EPrints::Plugin::Screen::REF_Support::can_be_viewed;
        return 0 if( !defined $rc || !$rc );

	return $self->can_select;
}

sub allow_search_authored { 1 }
sub allow_search_deposited { 1 }
sub allow_search_authored_all { 1 }
sub allow_search_deposited_all { 1 }

sub allow_select { shift->can_select }
sub allow_unselect { shift->allow_select }
sub allow_sync { shift->allow_select }

sub wishes_to_export { shift->{session}->param( "ajax" ) }
sub export_mimetype { "text/html; charset=utf-8" }

sub export { shift->EPrints::Plugin::Screen::REF_Support::export }

sub properties_from
{
	my( $self ) = @_;

	$self->EPrints::Plugin::Screen::REF_Support::properties_from;
	$self->EPrints::Plugin::Screen::AbstractSearch::properties_from;

	$self->{processor}->{dataset} = $self->{session}->dataset( "ref_support_selection" );
}

sub from
{
	my( $self ) = @_;

	my $action = $self->{processor}->{action};
	$action = $self->{session}->config( 'ref_support', 'default_search' ) || '' if( !defined $action );

	$self->search_from( $action );
	$action = $self->{processor}->{action};
	$self->EPrints::Plugin::Screen::from;

	if( $action =~ /^search/ )
	{
		$self->run_search;
	}

}

sub redirect_to_me_url
{
	my( $self ) = @_;

	# landing from another plugin, so make sure we clear any POSTs
	if( $self->{session}->param( "screen" ) ne $self->get_subtype )
	{
		return $self->EPrints::Plugin::Screen::REF_Support::redirect_to_me_url;
	}

	return $self->SUPER::redirect_to_me_url; # AbstractSearch
}

# Copied from AbstractSearch but without the brain-dead actions override
sub search_from
{
	my( $self, $action ) = @_;

	if( $action =~ /^search_/ )
	{
		$self->{processor}->{action} = $action;
	}
	
	$self->{processor}->{search} = new EPrints::Search(
			keep_cache => 1,
			for_web => 1,
			session => $self->{session},
			filters => [$self->search_filters],
			dataset => $self->{session}->dataset( 'eprint' ),
			%{$self->{processor}->{sconf}} );

	if(
		$action eq "search" ||
		$action eq "update" ||
		$action =~ /^search_/
	  )
	{
		foreach my $sf ( $self->{processor}->{search}->get_non_filter_searchfields )
		{
			my $prob = $sf->from_form();
			if( defined $prob )
			{
				$self->{processor}->add_message( "warning", $prob );
			}
		}
		my $exp = $self->{session}->param( "exp" );
		$self->{processor}->{search}->from_string( $exp )
			if EPrints::Utils::is_set( $exp );
	}
	if( $action eq "search" || $action eq "update" )
	{
		if( $self->{processor}->{search}->is_blank )
		{
			$self->{processor}->add_message( "warning",
				$self->{session}->html_phrase(
					"lib/searchexpression:least_one" ) );
			$self->{processor}->{action} = "";
		}
	}


	my $anyall = $self->{session}->param( "satisfyall" );

	if( defined $anyall )
	{
		$self->{processor}->{search}->{satisfy_all} = ( $anyall eq "ALL" );
	}

	my $order_opt = $self->{session}->param( "order" );
	if( !defined $order_opt )
	{
		$order_opt = "";
	}

	my $allowed_order = 0;
	foreach my $order_key ( keys %{$self->{processor}->{sconf}->{order_methods}} )
	{
		$allowed_order = 1 if( $order_opt eq $self->{processor}->{sconf}->{order_methods}->{$order_key} );
	}

	if( $allowed_order )
	{
		$self->{processor}->{search}->{custom_order} = $order_opt;
	}
	else
	{
		$self->{processor}->{search}->{custom_order} =
			$self->{processor}->{sconf}->{order_methods}->{$self->{processor}->{sconf}->{default_order}};
	}
}

sub action_search_authored {}
sub action_search_deposited {}
sub action_search_authored_all {}
sub action_search_deposited_all {}

sub action_select
{
	my( $self ) = @_;

	my $repo = $self->{session};

	$self->_action_redirect;

	my $search = $self->{processor}->{search};
	my $eprintid = $repo->param( "eprint" );
	my $dataset = $self->{processor}->{dataset};

	my $user = $repo->current_user;
	my $role = $self->{processor}->{role};
	my $benchmark = $self->{processor}->{benchmark};

	$search->add_field(
		$search->{dataset}->field( "eprintid" ),
		$eprintid,
		"EX"
	);

	my $eprint = $search->perform_search->item( 0 );

	if( !defined $eprint )
	{
		EPrints->abort( "Permissions error" );
	}

	# already selected
	my $selection = $dataset->dataobj_class->new_from_parts(
		$repo,
		eprint => $eprint,
		user => $role,
	);
	if( !defined $selection )
	{
		$selection = $dataset->dataobj_class->create_from_parts(
			$repo,
			eprint => $eprint,
			user => $role,
			user_actual => $user,
		);
	}

	$selection->select_for( $benchmark, $role->value( "ref_support_uoa" ) );
	$selection->commit;

}

sub action_unselect
{
	my( $self ) = @_;

	my $repo = $self->{session};

	$self->_action_redirect;

	my $selectionid = $repo->param( "selection" );
	my $dataset = $self->{processor}->{dataset};

	my $user = $repo->current_user;
	my $role = $self->{processor}->{role};
	my $benchmark = $self->{processor}->{benchmark};

	my $selection = $dataset->dataobj( $selectionid );
	return if !defined $selection;

	if( $role->id != $selection->value( "user_id" ) )
	{
		EPrints->abort( "Permissions error" );
	}

	$selection->unselect_for( $benchmark );
	$selection->commit;

}

sub action_sync
{
	my( $self ) = @_;

	my $repo = $self->{session};

	$self->_action_redirect;

	my $selectionid = $repo->param( "selection" );
	my $dataset = $self->{processor}->{dataset};

	my $user = $repo->current_user;
	my $role = $self->{processor}->{role};
	my $benchmark = $self->{processor}->{benchmark};

	my $selection = $dataset->dataobj( $selectionid );
	return if !defined $selection;

	if( $role->id != $selection->value( "user_id" ) )
	{
		EPrints->abort( "Permissions error" );
	}

	$selection->unselect_for( $benchmark );
	$selection->select_for( $benchmark, $role->value( "ref_support_uoa" ) );
	$selection->commit;
}

sub search_filters
{
	my( $self ) = @_;
	# any pre-defined searches?
	my $action = $self->{processor}->{action};

	my @filters = $self->SUPER::search_filters;

	my $ds = $self->{session}->dataset( "eprint" ); 

	if( $action )
	{
		if( $action =~ /^search_authored/ )
		{
			# enable this by setting $c->{"ref_support"}->{search_authored}->{by_id} = 1
			if( $self->{session}->config( 'ref_support', 'search_authored', 'by_id' ) )
			{
				# perhaps we need to use custom fields to do the matching between user "id" and eprint "ids"
				# the default is to match a user's email to the creators_id field
				my $fields = $self->{session}->config( 'ref_support', 'search_authored', 'by_id_fields' ) || {};
				my $user_field = $fields->{user_field} || 'email';
				my $eprint_field = $fields->{eprint_field} || 'creators_id';
				my $author_id = $self->{processor}->{role}->get_value( $user_field ) || 'UNSPECIFIED';
				push @filters, { meta_fields => [ $eprint_field ], value => $author_id, match => 'EX', describe => 0 };
			}
			else
			{
				my $author_name = $self->{processor}->{role}->get_value( "name" );

				my $search_string = $author_name->{family};
				if( defined $author_name->{given} && length $author_name->{given} )
				{
					$search_string .= ",".substr( $author_name->{given}, 0, 1 );
				}
				
				push @filters,
				     { meta_fields=>[ 'creators_name' ], value=> $search_string };
			}
		}
		elsif( $action =~ /^search_deposited/ )
		{
			push @filters,
				{ meta_fields=>[ 'userid' ], value=> $self->{processor}->{role}->get_id, match=>'EX', describe=>0 };
		}

		if( $action eq 'search_authored' || $action eq 'search_deposited' )
		{
			if( $ds->has_field( "hoa_exclude" ) && $self->{session}->config( 'ref_support', 'use_exclude' ) )
			{
				push @filters,
					{ meta_fields => [ 'hoa_exclude' ], value => 'FALSE', match => 'EX' };
			}

			push @filters,
				{ meta_fields=>[ 'date' ], value=> $self->{session}->config( 'ref_support', 'first_year' ) . "-", match=>'EX', describe=>0 };
		}
	}

	# and filter on the datasets:
	my $datasets = $self->{session}->config( 'ref_support', 'listing_search_datasets' ) || 'archive';
	push @filters,  { meta_fields => [ 'eprint_status' ], value=> $datasets, match => 'IN', merge => 'ANY' };

	return @filters;
}

sub render_action_link
{
	my( $self ) = @_;

	local $self->{processor}->{role};
	$self->SUPER::render_action_link;
}

sub render_title { shift->EPrints::Plugin::Screen::render_title }

sub render_predefined_searches
{
	my( $self ) = @_;

	my $session = $self->{session};

	my $chunk = $session->make_doc_fragment;

	my $search_desc = $session->make_doc_fragment;
	my $current_action = $self->{processor}->{action};

	my @predef_searches_order = ( 'search_authored', 'search_authored_all', 'search_deposited', 'search_deposited_all', 'newsearch' );
	my %predef_searches = map { $_ => 1 } @predef_searches_order;

	my $base_url = URI->new(
		$session->config( "http_cgiroot" ) . "/users/home",
	);
	$base_url->query_form( screen => $self->{processor}->{screenid} );

	if( defined $current_action && $predef_searches{$current_action} )
	{
		delete $predef_searches{$current_action};
		my $is_uoa_champion = ( $session->current_user->get_id != $self->{processor}->{role}->get_id ) ? 1 : 0;

		my $ul = $search_desc->appendChild( $session->make_element( 'ul' ) );
		
		my $who = $session->make_doc_fragment;
		if( $is_uoa_champion )
		{
			my $span = $session->make_element( 'span', class => 'ep_ref_listing_role' );
			$span->appendChild( $self->{processor}->{role}->render_value( 'name' ) );
			$who->appendChild( $span );
			$who->appendChild( $session->make_text( " has" ) );
		}
		else
		{
			$who->appendChild( $session->make_text( "you have" ) );
		}

		my $ds = $self->{session}->dataset( "eprint" ); 

		foreach my $searchid ( @predef_searches_order )
		{
			next unless( defined $predef_searches{$searchid} );
			my $li = $ul->appendChild( $session->make_element( 'li' ) );

			my $link = $li->appendChild( $session->render_link( $base_url."&_action_$searchid=1" ) );

			my %params;
			$params{who} = $session->clone_for_me( $who, 1 ) if( $searchid ne 'newsearch' );

			#render custom phrase if using REF CC exclude field
	                if( $ds->has_field( "hoa_exclude" ) && $self->{session}->config( 'ref_support', 'use_exclude' ) &&
				( ( $searchid eq "search_authored" ) || ( $searchid eq "search_deposited" ) ) )
                        {
                                $link->appendChild( $session->html_phrase( "ref/listing:$searchid:exclude:desc", %params ) );
                        }
			else
			{	
				$link->appendChild( $session->html_phrase( "ref/listing:$searchid:desc", %params ) );
			}
		}
	
		my $search_phrase = $session->html_phrase( "ref/listing:$current_action:desc", who => $session->clone_for_me( $who, 1 ) );

		#render custom phrase if using REF CC exclude field
		if( $ds->has_field( "hoa_exclude" ) && $self->{session}->config( 'ref_support', 'use_exclude' ) &&
			( ( $current_action eq "search_authored" ) || ( $current_action eq "search_deposited" ) ) ) 
                {
				$search_phrase = $session->html_phrase( "ref/listing:$current_action:exclude:desc", who => $session->clone_for_me( $who, 1 ) );
	        }
		$search_desc->appendChild( $session->html_phrase( "ref/listing:searches:heading", search_desc => $search_phrase, other_searches => $ul ) );
	}

	$chunk->appendChild( $search_desc );

	return $chunk;
}

sub render_search_form
{
	my( $self ) = @_;

	my $chunk = $self->{session}->make_doc_fragment;

	return $chunk if !$self->can_select;

	# Adds some pre-defined searches
	$chunk->appendChild( $self->render_predefined_searches );

	# The actual search form:
	$chunk->appendChild( $self->SUPER::render_search_form() );

	return $chunk;
}

sub paginate_opts
{
	my( $self ) = @_;

	my %opts = $self->SUPER::paginate_opts;

	my $action = $self->{processor}->{action};
	
	if( ($action =~ /^search_authored/) || ($action =~ /^search_deposited/ ) )
	{
		delete $opts{params}->{_action_search};
		$opts{params}->{"_action_$action"} = 1;
	
		# sf2 - this must re-set, otherwise the current action name is lost 	
		if( defined $opts{controls_after} )
		{
			delete $opts{controls_after};
			my $escexp = $self->{processor}->{search}->serialise;
			my $order_div = $self->{session}->make_element( "div", class=>"ep_search_reorder" );
			my $form = $self->{session}->render_form( "GET" );
			$order_div->appendChild( $form );
			$form->appendChild( $self->{session}->html_phrase( "lib/searchexpression:order_results" ) );
			$form->appendChild( $self->{session}->make_text( ": " ) );
			$form->appendChild( $self->render_order_menu );

			$form->appendChild( $self->{session}->render_button(
						name=>"_action_$action",
						value=>$self->{session}->phrase( "lib/searchexpression:reorder_button" ) ) );
			$form->appendChild( $self->render_hidden_bits );
			$form->appendChild(
					$self->{session}->render_hidden_field( "exp", $escexp, ) );
			$opts{controls_after} = $order_div;
		}
	}

	return %opts;
}

# called 'internally' by AbstractSearch.pm
sub render_result_row 
{
	my ( $self, $repo, $eprint, $searchexp, $n ) = @_;
	
	my $dataset = $self->{processor}->{dataset};
	my $role = $self->{processor}->{role};
	my $user = $repo->current_user;
	my $benchmark = $self->{processor}->{benchmark};

	my $phraseid = "ref/select:selected_by";
	
	my $tr = $repo->make_element( "tr" );

	if( defined $n )
	{
		my $td_n = $repo->make_element( "td" );
		my $span = $repo->make_element( "span", "style"=>"font-weight:bold;" );
		$span->appendChild( $repo->make_text( "$n." ) );
		$td_n->appendChild( $span );
		$tr->appendChild( $td_n );
	}

	# Each row contains a citation...
	my $td_cite = $repo->make_element( "td" );
	$tr->appendChild( $td_cite );

	# Use REF CC citation style if available, otherwise use style defined by search configuration
	my $ref_cc_compliance = $self->get_ref_cc_compliance( $repo, $eprint );
	if( $ref_cc_compliance == -1 )
	{
		$td_cite->appendChild( $eprint->render_citation_link( $searchexp->{citation} ) );
	}
	else
	{
		$td_cite->appendChild( $eprint->render_citation_link( "ref_cc", compliance => [$ref_cc_compliance,"INTEGER"] ) );
	}
	

	# ... a list of other users related to that item ...
	my $td_users = $repo->make_element( "td" );
	my $already_selected = 0;
	my @names;
	$benchmark->eprint_selections( $eprint )->map(sub {
		my( undef, undef, $other ) = @_;

		my $user_id = $other->value( "user_id" );
		if( $user_id == $role->id )
		{
			$already_selected = 1;
			return;
		}

		my $user = $repo->user( $user_id );
		if( defined $user )
		{
			push @names, EPrints::Utils::tree_to_utf8( $user->render_description );
		} 
		else 
		{
			push @names, $repo->phrase( "ref:unknown_user", id => $user_id );
		}
	});
	if( scalar( @names ) > 0 )
	{
		$td_users->appendChild( $repo->html_phrase( $phraseid, 
			names => $repo->make_text( join(", ", @names) ) ) );
	}
	$tr->appendChild( $td_users );
	
	# ... and an action button
	my $td_act = $repo->make_element( "td" );
	
	if( !$already_selected )
	{
		my $uri = URI->new( $repo->current_url( query => 1 ) );
		$uri->query_form(
			screen => $self->{processor}->{screenid},
			role => $role->id,
			user => $user->id,
			eprint => $eprint->id,
			_action_select => 1,
			params => $uri->query,
		);

		my $button = $repo->make_element( "a", href => "$uri",
				onclick => "",
		); 
		$button->appendChild( $repo->html_phrase( "ref/select:add_button" ) );

		$td_act->appendChild( $button );	
	}
	else
	{
		$td_act->appendChild( $repo->html_phrase( "ref/select:already_selected" ) );	
	}

	$tr->appendChild( $td_act );

	return $tr;
}

sub render_export_bar
{
	return shift->{session}->make_doc_fragment;
}

sub render_selections
{
	my( $self ) = @_;

	my $repo = $self->{session};
	my $processor = $self->{processor};
	my $dataset = $processor->{dataset};
	my $role = $processor->{role};
	my $user = $repo->current_user;
	my $benchmark = $self->{processor}->{benchmark};

	my $selections = $benchmark->user_selections( $role );
	return $repo->html_phrase( "ref/select:none_selected" )
		if $selections->count == 0;

	my $table = $repo->make_element( "table", class=>"ref_current_selections" );

	# first need to find out any "reserved" outputs, format of the hash above is $reserved_id => $double_weighted_id
	my $reserves = {};
	$selections->map(sub {
		my( undef, undef, $selection ) = @_;

		if( $selection->is_set( 'reserve' ) )
		{
			$reserves->{$selection->get_value( 'reserve' )} = $selection->get_id;
		}
	} );

	my $n = 1;
	$selections->map(sub {
		my( undef, undef, $selection ) = @_;

		my $eprintid = $selection->value( 'eprint_id' );
		my $eprint = $repo->dataset( "eprint" )->dataobj( $eprintid );

		# this is to flag whether the eprint object exists or not:
		my $eprint_exists = 1;
		if( !defined $eprint )
		{
			$eprint = $repo->dataset( "eprint" )->make_object( $repo, { eprintid => $eprintid, eprint_status => 'inbox' } );
			$eprint_exists = 0;
		}

		my @names;
		my $others = $repo->make_doc_fragment;
		$benchmark->eprint_selections( $eprint )->map(sub {
			my( undef, undef, $other ) = @_;

			my $user_id = $other->value( "user_id" );
			if( $user_id == $role->id )
			{
				return;
			}

			my $user = $repo->user( $user_id );
			if( defined $user )
			{
				push @names, EPrints::Utils::tree_to_utf8( $user->render_description );
			} 
			else 
			{
				push @names, $repo->phrase( "ref:unknown_user", id => $user_id );
			}
		}) if( $eprint_exists );

		if( scalar( @names ) > 0 )
		{
			$others->appendChild( $repo->html_phrase( 'ref/select:also_selected_by',
						names => $repo->make_text( join(", ", @names) ) ) );
		}

		my $uoaid = $selection->uoa( $benchmark );
		my $uoa = $repo->dataset( "subject" )->dataobj( $uoaid );
		if( !defined $uoa )
		{
			$uoa = $repo->dataset( "subject" )->make_object( $repo,
				{ subjectid => $uoaid }
			);
		}

		my $actions = $repo->make_element( "ul",
			style => "margin: 0 0; padding: 0 0; list-style-type: none;",
		);

		if( $self->can_select )
		{
			my $li = $repo->make_element( "li" );
			$actions->appendChild( $li );
			my $uri = URI->new( $repo->current_url( query => 1 ) );
			$uri->query_form(
				screen => $self->{processor}->{screenid},
				selection => $selection->id,
				role => $role->id,
				_action_unselect => 1,
				params => $uri->query,
			);
			my $link = $repo->render_link( "$uri" );
			$link->appendChild( $repo->html_phrase( "ref/select:remove_button" ) );
			$li->appendChild( $link );

			# edit selection
			$li = $repo->make_element( "li" );
			$actions->appendChild( $li );
			$link = $repo->render_link( $selection->get_control_url );
			$link->appendChild( $repo->html_phrase( "ref/select:qualify_button" ) );
			$li->appendChild( $link );

			# synchronise UoA
			if( $uoa->id ne $role->value( "ref_support_uoa" ) )
			{
				$uri = URI->new( $repo->current_url( query => 1 ) );
				$uri->query_form(
					screen => $self->{processor}->{screenid},
					selection => $selection->id,
					role => $role->id,
					_action_sync => 1,
					params => $uri->query,
				);
				$li = $repo->make_element( "li" );
				$actions->appendChild( $li );
				$link = $repo->render_link( "$uri" );
				$link->appendChild( $self->html_phrase( "action:sync:title" ) );
				$li->appendChild( $link );
			}
		}

		my $is_reserve = $repo->make_doc_fragment;
		if( $reserves->{$selection->get_id} )
		{
			$is_reserve = $self->html_phrase( "reserved", "for" => $repo->make_text( $reserves->{$selection->get_id} ) )
		}

		#render REF CC citation if appropriate
		my $ref_cc_compliance = $self->get_ref_cc_compliance( $repo, $eprint );
		if( $ref_cc_compliance == -1 )
		{
			$table->appendChild( $selection->render_citation( 'action',
				n => [ $n++, 'INTEGER' ],
				actions => [ $actions, 'XHTML' ],
				others => [ $others, 'XHTML' ],
				#uoa => [ $uoa->render_description, 'XHTML' ],
				eprint_exists => [ $eprint_exists, 'BOOLEAN' ],
				is_reserve => [ $is_reserve, 'XHTML' ]
			) );
		}
		else
		{
			$table->appendChild( $selection->render_citation( 'ref_cc_action',
				n => [ $n++, 'INTEGER' ],
				actions => [ $actions, 'XHTML' ],
				others => [ $others, 'XHTML' ],
				#uoa => [ $uoa->render_description, 'XHTML' ],
				eprint_exists => [ $eprint_exists, 'BOOLEAN' ],
				is_reserve => [ $is_reserve, 'XHTML' ],
				compliance => [$ref_cc_compliance,"INTEGER"]
			) );
		}
	});

	return $table;
}

sub render_results
{
	my( $self ) = @_;

	my $chunk = $self->{session}->make_doc_fragment;

	return $chunk
		if !$self->can_select;

	# Adds some pre-defined searches
	$chunk->appendChild( $self->render_predefined_searches );

	$chunk->appendChild( $self->SUPER::render_results );

	return $chunk;
}

# sf2 - render(): 
# if no current benchmark exists -> render a message (saying there's nothing to select against)
# if a benchmark exists -> render the selections + the name of the benchmark + the search form
sub render
{
	my( $self ) = @_;

	my $repo = $self->{session};
	my $frag = $repo->make_doc_fragment;

	# landed from another plugin but we still need our init for searching
	if( !defined $self->{processor}->{search} )
	{
		delete $self->{processor}->{action};
		$self->properties_from;
		$self->from;
	}

	# search form
	my $results;
	if( $self->{processor}->{results} )
	{
		$results = $self->render_results;
	}
	else
	{
		$results = $self->render_search_form;
	}

	# sf2 / Placeholder phrase (empty by default, useful for Admins if they need
	# to address the users)
	$frag->appendChild( $self->html_phrase( 'message' ) );

	my $is_uoa_champion = $repo->current_user->exists_and_set( 'ref_support_uoa_role' );

	my %inserts;
	$inserts{selections} = $self->render_selections;
	$inserts{results} = $results;
	$inserts{messages} = $self->render_warnings;
	
	if( $is_uoa_champion )
	{
		# "top tools" for the UoA Champions
		$inserts{top_tools} = $repo->html_phrase( 'ref:top_tools:champion', 
			tools => $self->render_tools,
			benchmarks => $self->render_benchmarks( "ref:benchmarks_tools" ),
			roles => $self->render_roles 
		);
	}
	else
	{
		# ... and for research staff (non-champions)
		$inserts{top_tools} = $repo->html_phrase( 'ref:top_tools:researcher',
			benchmark => $self->{processor}->{benchmark}->render_citation,
			benchmarks => $self->render_benchmarks( "ref:benchmarks_tools:researcher" )
		);
	}
		
	$frag->appendChild( $self->{processor}->{role}->render_citation(
				'ref_support_listing_page',
				can_select => $self->can_select,
				pindata => { inserts => \%inserts },
	) );

	return $frag;
}

sub get_controls_before
{
        my( $self ) = @_;
        my $cacheid = $self->{processor}->{results}->{cache_id};
        my $escexp = $self->{processor}->{search}->serialise;

	my $action = $self->{processor}->{action};

        my $baseurl = $self->{session}->get_uri . "?cache=$cacheid&exp=$escexp&screen=".$self->{processor}->{screenid};
        $baseurl .= "&order=".$self->{processor}->{search}->{custom_order};
        my @controls_before;

	# "update" aka "Refine search" doesn't work with the predefined search so don't show the link
	if( $action !~ /^search_/ )
	{
                push @controls_before, {
                        url => "$baseurl&_action_update=1",
                        label => $self->{session}->html_phrase( "lib/searchexpression:refine" ),
                };
	}
	push @controls_before, {
                        url => $self->{session}->get_uri . "?screen=".$self->{processor}->{screenid},
                        label => $self->{session}->html_phrase( "lib/searchexpression:new" ),
                };

        return @controls_before;
}

sub get_ref_cc_compliance
{
	my( $self, $repo, $eprint ) = @_;

	my $compliance = -1;

	if( $eprint->get_dataset->has_field( "hoa_compliant" ) )
	{
		# check we are the relevant item type
		my $type = $eprint->value( "type" );
		my $compliant_type = 0;
		foreach my $t (@{$repo->config( "hefce_oa", "item_types" )})
		{
			if( $type eq $t )
			{
				$compliant_type = 1;
			}
		}
		if( $compliant_type )
		{
			my $flag = $eprint->value( "hoa_compliant" );
			$compliance = 0; # not compliant
			if ( $flag & HefceOA::Const::COMPLIANT )
			{
				$compliance = 1; # compliant
			}
			elsif( $flag & HefceOA::Const::DEP &&
				$flag & HefceOA::Const::DIS &&
				$flag & HefceOA::Const::ACC_EMBARGO &&
				$repo->call( ["hefce_oa", "could_become_ACC_TIMING_compliant"], $repo, $eprint ) )
			{
				$compliance = 2; # future compliance
			}

			if( $repo->can_call( "hefce_oa", "OUT_OF_SCOPE_reason" ) )
			{
				my $out_of_scope = $repo->call( [ "hefce_oa", "OUT_OF_SCOPE_reason" ], $repo, $eprint );
				if( $out_of_scope )
				{
                    if( $out_of_scope eq "gold" )
                    {
	    				$compliance = 1; # compliant
                    }
                    else
                    {
	    				$compliance = 3; # compliance not relevant
                    }
				}
			}
		}
	}
	return $compliance;
}

1;
