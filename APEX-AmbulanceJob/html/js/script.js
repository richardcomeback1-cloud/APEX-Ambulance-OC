$(function () {
    let hideDeadScreenTimer = null

    function display(bool) {
        const deadScreen = $('.display_dead_screen');

        if (hideDeadScreenTimer) {
            clearTimeout(hideDeadScreenTimer);
            hideDeadScreenTimer = null;
        }

        if (bool) {
            deadScreen.stop(true, true).css('display', 'block').removeClass('fade-out').addClass('fade-in');
        } else {
            deadScreen.removeClass('spawn_time fade-in').addClass('fade-out');
            hideDeadScreenTimer = setTimeout(function() {
                deadScreen.css('display', 'none').removeClass('fade-out');
                hideDeadScreenTimer = null;
            }, 220);
        }
    }

    opacity = function() {
        $("#ped").css('opacity','0.4');
    };

    respawn = function() {
        $(".body-loading").show();
        $(".probar").slideDown(0)
        $(".probar").stop().css({"width": 0}).animate({
        width: '70%'
        }, {
        duration: parseInt(4000),
        complete: function() {
            $(".probar").css("width", 0);
            $(".body-loading").hide();
        }
        });
    };

    ropacity = function() {
        $("#ped").css('opacity','1');
    };

    window.addEventListener('message', function(event) {
        var item = event.data;

        if (item.action == 'G') {
            if (item.hide == true) {
                $('.display_dead_screen').removeClass('spawn_time')
            } else {
                $('.display_dead_screen').addClass('spawn_time')
            }
        }
        if (item.action == 'talk') {
            // console.log("AMBULANCE CHECK ",false)
            if(item.bool){
                $('.sound_dead').fadeIn()
            }
            else{
                $('.sound_dead').fadeOut()
            }
        }
        if (item.type === "ui") {
            if (item.title_show){
                $('.title_show').html(item.title_show)
            }
            else{
                $('.title_show').html('You are incapacitated. Please wait for emergency service')
            }
            if (item.status == true) {
                display(true)
                $('.add_on_respawn').fadeOut()
                $('.display_dead_screen').removeClass('spawn_time')
                $('#playerid').html(item.id);
                $("#clearped").removeClass('cooldown');
                $("#signal").removeClass('cooldown');
                $("#requesttalk").removeClass('cooldown');
                $("#gang").removeClass('cooldown');
                $(".time_ANI").css('animation','');
                // $(".load").css('background','#e44646');
                // $("#police").show();
                // ropacity();
            } else {
                display(false)
            }
        } else if (item.type === "addclass") {
            // console.log('[DEBUG] NUI addclass:', item.status, $('#clearped')[0]);
            if (item.status == true) {
                $("#clearped").addClass('cooldown');
            } else {
                $("#clearped").removeClass('cooldown');
            }
        } else if (item.type === "time") {
            $(".time_dead_text").html(item.time);
        } else if (item.type === "sendsignal") {
            if (item.status == true) {
                $("#signal").addClass('cooldown');
            } else {
                $("#signal").removeClass('cooldown');
                
            }
        }
        else if (item.type == "progress"){
            newPercent =Math.floor(item.percent)
            $('.prog_loadbar_dead').css('background-size',newPercent+'%')
            // console.log(per)
        }
        else if (item.type === "requestTalk") {
            if (item.status == true) {
                // $("#requesttalk").addClass('accooldowntive');
                $("#requesttalk").addClass('cooldown');
            } else {
                $("#requesttalk").removeClass('cooldown');
            }
        } else if (item.type === "gang") {
            // console.log('GANG cooldown status:', item.status, $("#gang"));
            if (item.status == true) {
                $("#gang").addClass('cooldown');
            } else {
                $("#gang").removeClass('cooldown');
            }
        } else if (item.type === "police") {
            if (item.status == true) {
                $("#police").hide();
            } else {
                $("#police").show();
            }
        }
        else if (item.type === "bodyX") {
            $(".container").addClass('dead_sync')
        }
    })
})