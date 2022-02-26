package questionMaker;

import java.util.ArrayList;
import java.util.Scanner;

public class Questions2 {



	// Using Scanner for Getting Input from User
	ArrayList<String> ElseAnswers;
	Scanner in = new Scanner(System.in);
	String question="";
	String answer="";
	boolean endWhy = false;
	String continueOrSkip = "";
	String qnumeration;
	int count;
	int exit = 0;

	//what
	public void what() {
		String typeQuestion = "What";
		System.out.println("");
		System.out.println(typeQuestion.toUpperCase()+"?");
		String ElseAnswer = in.nextLine();
		continueOrSkip = "1";
		WElse(ElseAnswer,typeQuestion);
		ElseAnswers.forEach(response -> {
			int currentResponseNumber =ElseAnswers.indexOf(response)+1;
			System.out.println(typeQuestion+"R" + currentResponseNumber + ": " + response );
			WNumeration(typeQuestion,currentResponseNumber,response);
		});
		System.out.println("Hit enter or type the w question");
		continueOrSkip =in.nextLine();
		continueOrW(continueOrSkip);	
	}

	//why
	public void why() {
		String typeQuestion = "Why";
		System.out.println("");
		System.out.println(typeQuestion.toUpperCase()+"?");
		String ElseAnswer = in.nextLine();
		continueOrSkip = "1";
		WElse(ElseAnswer,typeQuestion);
		ElseAnswers.forEach(response -> {
			int currentResponseNumber =ElseAnswers.indexOf(response)+1;
			System.out.println(typeQuestion+"R" + currentResponseNumber + ": " + response );
			WNumeration(typeQuestion,currentResponseNumber,response);
		});
		System.out.println("Hit enter or type the w question");
		continueOrSkip =in.nextLine();
		continueOrW(continueOrSkip);
	}

	//how
	public void how() {
		String typeQuestion = "How";
		System.out.println("");
		System.out.println(typeQuestion.toUpperCase()+"?");
		String ElseAnswer = in.nextLine();
		continueOrSkip = "1";
		WElse(ElseAnswer,typeQuestion);
		ElseAnswers.forEach(response -> {
			int currentResponseNumber =ElseAnswers.indexOf(response)+1;
			System.out.println(typeQuestion+"R" + currentResponseNumber + ": " + response );
			WNumeration(typeQuestion,currentResponseNumber,response);
		});
		System.out.println("Hit enter or type the w question");
		continueOrSkip =in.nextLine();
		continueOrW(continueOrSkip);
	}

	//who
	public void who() {
		String typeQuestion = "Who";
		System.out.println("");
		System.out.println(typeQuestion.toUpperCase()+"?");
		String ElseAnswer = in.nextLine();
		continueOrSkip = "1";
		WElse(ElseAnswer,typeQuestion);
		ElseAnswers.forEach(response -> {
			int currentResponseNumber =ElseAnswers.indexOf(response)+1;
			System.out.println(typeQuestion+"R" + currentResponseNumber + ": " + response );
			WNumeration(typeQuestion,currentResponseNumber,response);
		});
		System.out.println("Hit enter or type the w question");
		continueOrSkip =in.nextLine();
		continueOrW(continueOrSkip);
	}

	//where
	public void where() {
		String typeQuestion = "Where";
		System.out.println("");
		System.out.println(typeQuestion.toUpperCase()+"?");
		String ElseAnswer = in.nextLine();
		continueOrSkip = "1";
		WElse(ElseAnswer,typeQuestion);
		ElseAnswers.forEach(response -> {
			int currentResponseNumber =ElseAnswers.indexOf(response)+1;
			System.out.println(typeQuestion+"R" + currentResponseNumber + ": " + response );
			WNumeration(typeQuestion,currentResponseNumber,response);
		});
		System.out.println("Hit enter or type the w question");
		continueOrSkip =in.nextLine();
		continueOrW(continueOrSkip);
	}

	//when
	public void when() {
		String typeQuestion = "When";
		System.out.println("");
		System.out.println(typeQuestion.toUpperCase()+"?");
		String ElseAnswer = in.nextLine();
		continueOrSkip = "1";
		WElse(ElseAnswer,typeQuestion);
		ElseAnswers.forEach(response -> {
			int currentResponseNumber =ElseAnswers.indexOf(response)+1;
			System.out.println(typeQuestion+"R" + currentResponseNumber + ": " + response );
			WNumeration(typeQuestion,currentResponseNumber,response);
		});
		System.out.println("Hit enter or type the w question");
		continueOrSkip =in.nextLine();
		continueOrW(continueOrSkip);
	}

	
	//method responsible for calling a question with the specified parameter
	public void callingQuestion(String questionType) {
		if (questionType.equals("what")) {
			what();
		}
		if (questionType.equals("why")) {
			why();
		}
		if (questionType.equals("how") ) {
			how();
		}
		if (questionType.equals("who")) {
			who();
		}
		if (questionType.equals("where")) {
			where();
		}
		if (questionType.equals("when")) {
			when();
		}
	}
	
	//method responsible for adding the else answers into the ElseAnswers
	public void WElse(String ElseAnswer, String questionType) {
		ElseAnswers = new ArrayList<String>();
		ElseAnswers.add(ElseAnswer);
		String Qelse = "1";
		int countElse = 2;
		while (Qelse.equals("1")) {
			System.out.println(countElse + ".- " + questionType + " else?");
			ElseAnswer = in.nextLine();
			ElseAnswers.add(ElseAnswer);
			countElse ++;
			System.out.println("exit else = 2");
			Qelse = input(in.nextLine());
		}
	}
	
	//method responsible for create questions for each of the else answers
	public void WNumeration(String questionType, int currentResponseNumber,String response) {
		qnumeration = "1";
		count =1;
		while (qnumeration.equals("1")) {
			
			System.out.println(questionType + count + ":");
			System.out.print("Q= ");
			question = in.nextLine();
			System.out.print("R= ");
			answer = in.nextLine();
			count++;
			// to skip or keep the w
			System.out.println("Continue = enter, " +" exit "+ questionType + "R" + currentResponseNumber + ": " + response + " = 2");
			qnumeration = input(in.nextLine());
			
		}
		
	}
	
	//method responsible for leading to the next question
	public void continueOrW(String getAnswer) {
		if (!(getAnswer.equals(""))) {
			if (getAnswer.equals("what")|| 
				getAnswer.equals("why")||
				getAnswer.equals("how")||
				getAnswer.equals("who")||
				getAnswer.equals("where")||
				getAnswer.equals("when")) {
				
				callingQuestion(getAnswer);
			}else {
				System.out.println("that is not a question");
			}
			
		}
	}
	
	public String input (String value) {
		if (value.equals("")) {
			return "1";
		}
		return value;
	}

}
