import 'package:fitrope_app/style.dart';
import 'package:flutter/material.dart';

enum CourseState {
  NULL,
  CAN_SUBSCRIBE,
  CANT_SUBSCRIBE,
  SUBSCRIBED
}

class CourseCard extends StatefulWidget {
  final String title;
  final TextStyle? titleStyle;
  final String description;
  final TextStyle? descriptionStyle;
  final Function? onClick;
  final Function? onClickAction;
  final CourseState courseState;

  const CourseCard({
    super.key, 
    required this.title,
    this.courseState=CourseState.NULL,
    this.titleStyle,
    this.description="",
    this.descriptionStyle,
    this.onClick,
    this.onClickAction
  });

  @override
  State<CourseCard> createState() => _CourseCardState();
}

class _CourseCardState extends State<CourseCard> {
  Widget renderTitle() {
    if(widget.titleStyle != null) {
      return Text(widget.title, overflow: TextOverflow.visible, style: widget.titleStyle,);
    }

    return Text(widget.title, style: const TextStyle(color: Colors.white, ),);
  }

  Widget renderButton() {
    late String buttonText;
    late Color buttonColor;
    late Color buttonTextColor;
    bool canBeClicked = false;

    if(widget.courseState == CourseState.CAN_SUBSCRIBE) {
      canBeClicked = true;
      buttonText = 'Prenotati';
      buttonColor = actionColor;
      buttonTextColor = Colors.white;
    }
    else if(widget.courseState == CourseState.CANT_SUBSCRIBE) {
      buttonText = 'Non disponibile';
      buttonColor = ghostColor;
      buttonTextColor = const Color.fromARGB(86, 255, 255, 255);
    }
    else if(widget.courseState == CourseState.SUBSCRIBED) {
      buttonText = 'Iscritto';
      buttonColor = ghostColor;
      buttonTextColor = const Color.fromARGB(86, 255, 255, 255);
    }

    return ElevatedButton(
      onPressed: canBeClicked ? () {
        if(widget.onClickAction != null) {
          widget.onClickAction!();
        }
      } : null,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(buttonColor),
        padding: WidgetStateProperty.all(const EdgeInsets.only(top: 0, left: 10, right: 10, bottom: 0)),
        shape: WidgetStateProperty.all<RoundedRectangleBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          )
        )
      ), 
      child: Text(buttonText, style: TextStyle(color: buttonTextColor),),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if(widget.onClick != null) {
          widget.onClick!();
        }
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: const BoxDecoration(
          color: primaryColor,
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    renderTitle(),
                  ],
                ),
                if(widget.description != "") const SizedBox(height: 10,),
                if(widget.description != "") Text(widget.description, style: const TextStyle(color: Colors.white, ),)
              ],
            ),
            if(widget.courseState != CourseState.NULL)renderButton()
          ],
        )
      ),
    );
  }
}