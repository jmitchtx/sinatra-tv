$(function() {
  $(document).delegate('.links.filter.by.name a', 'click', function(event){
    letter = $(this).attr('href')[1];
    $(".show").show();
    if (letter != 't'){
      $(".show:not([name^='" + letter + "'])").hide();
    }
    event.preventDefault();
  });

  $(document).delegate('.remote a', 'click', function(event){
    partial = $(this).closest('.partial');
    href = $(this).attr('href');
    if (partial.length > 0){
      $(partial).load(href);
    }else{
      $.get(href)
    }
    event.preventDefault();
  });

  $(document).delegate('.async a', 'click', function(event){
    href = $(this).attr('href');
    $.get(href)
    event.preventDefault();
  });
});
