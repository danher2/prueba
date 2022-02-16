package questionMaker;

import java.util.Scanner;

public class Questions2 {

	Answers answer = new Answers();

	// Using Scanner for Getting Input from User
	Scanner in = new Scanner(System.in);
	boolean endWhy = false;
	String lastAnswer = "";
	String lastQuestion = "";
	String whyanswer;
	String whyHowAnswer;
	String skipOrKeep="";
	int count = 2;
	int exit = 0;

	public void what() {

		// what
		System.out.println("");
		System.out.println("");
		System.out.println("What happen?");
		answer.setWhatAnswer(in.nextLine());
		answer.setWhatAnswer(in.nextLine());
		while (answer.getWhatAnswer().equals("1")) {
			lastAnswer = answer.getWhatAnswer();
			System.out.println("");
			System.out.println("what " + count + ":");
			System.out.print("Q= ");
			answer.setWhatQuestion(in.nextLine());
			lastQuestion = answer.getWhatQuestion();
			System.out.print("R= ");
			answer.setWhatAnswer(in.nextLine());
			lastAnswer = answer.getWhatAnswer();
			count++;
			// to skip or keep the w
			answer.setWhatAnswer(in.nextLine());
			
		}
			if (!(answer.getWhatAnswer().equals("2"))) {
				if (answer.getWhatAnswer().equals("what")|| 
					answer.getWhatAnswer().equals("why")||
					answer.getWhatAnswer().equals("how")||
					answer.getWhatAnswer().equals("who")||
					answer.getWhatAnswer().equals("where")||
					answer.getWhatAnswer().equals("when")) {
					
					callingQuestion(answer.getWhatAnswer());
				}else {
					System.out.println("that is not a question");
				}
				
			}
			
	}

	public void why() {
		// why
		count = 2;
		System.out.println("");
		System.out.println("");
		System.out.println("Why did it happen?");
		answer.setWhyAnswer(in.nextLine());
		answer.setWhyAnswer(in.nextLine());
		while ((answer.getWhyAnswer().equals("1"))) {
			lastAnswer = answer.getWhyAnswer();
			System.out.println("");
			System.out.println("why " + count + ":");
			System.out.print("Q= ");
			answer.setWhyQuestion(in.nextLine());
			lastQuestion = answer.getWhyQuestion();
			System.out.print("R= ");
			answer.setWhyAnswer(in.nextLine());
			lastAnswer = answer.getWhyAnswer();
			count++;
			// to skip or keep the w
			answer.setWhyAnswer(in.nextLine());
			
		}
		if (!(answer.getWhyAnswer().equals("2"))) {
			if (answer.getWhyAnswer().equals("what")|| 
				answer.getWhyAnswer().equals("why")||
				answer.getWhyAnswer().equals("how")||
				answer.getWhyAnswer().equals("who")||
				answer.getWhyAnswer().equals("where")||
				answer.getWhyAnswer().equals("when")) {
				
				callingQuestion(answer.getWhyAnswer());
			}else {
				System.out.println("that is not a question");
			}
			
		}

	}

	public void how() {
		// how
		count = 2;
		System.out.println("");
		System.out.println("");
		System.out.println("How did it happen?");
		answer.setHowAnswer(in.nextLine());
		answer.setHowAnswer(in.nextLine());
		while ((answer.getHowAnswer().equals("1"))) {
			lastAnswer = answer.getHowAnswer();
			System.out.println("");
			System.out.println("how " + count + ":");
			System.out.print("Q= ");
			answer.setHowQuestion(in.nextLine());
			lastQuestion = answer.getHowQuestion();
			System.out.print("R= ");
			answer.setHowAnswer(in.nextLine());
			lastAnswer = answer.getHowAnswer();
			count++;
			// to skip or keep the w
			answer.setHowAnswer(in.nextLine());
			
		}
		if (!(answer.getHowAnswer().equals("2"))) {
			if (answer.getHowAnswer().equals("what")|| 
				answer.getHowAnswer().equals("why")||
				answer.getHowAnswer().equals("how")||
				answer.getHowAnswer().equals("who")||
				answer.getHowAnswer().equals("where")||
				answer.getHowAnswer().equals("when")) {
				
				callingQuestion(answer.getHowAnswer());
			}else {
				System.out.println("that is not a question");
			}
			
		}

	}

	public void who() {

		// who
		count = 2;
		System.out.println("");
		System.out.println("");
		System.out.println("who is involved?");
		answer.setWhoAnswer(in.nextLine());
		answer.setWhoAnswer(in.nextLine());
		while ((answer.getWhoAnswer().equals("1"))) {
			lastAnswer = answer.getWhoAnswer();
			System.out.println("");
			System.out.println("who " + count + ":");
			System.out.print("Q= ");
			answer.setWhoQuestion(in.nextLine());
			lastQuestion = answer.getWhoQuestion();
			System.out.print("R= ");
			answer.setWhoAnswer(in.nextLine());
			lastAnswer = answer.getWhoAnswer();
			count++;
			// to skip or keep the w
			answer.setWhoAnswer(in.nextLine());
			
		}
		if (!(answer.getWhoAnswer().equals("2"))) {
			if (answer.getWhoAnswer().equals("what")|| 
				answer.getWhoAnswer().equals("why")||
				answer.getWhoAnswer().equals("how")||
				answer.getWhoAnswer().equals("who")||
				answer.getWhoAnswer().equals("where")||
				answer.getWhoAnswer().equals("when")) {
				
				callingQuestion(answer.getWhoAnswer());
			}else {
				System.out.println("that is not a question");
			}
			
		}
	}

	public void where() {
		// where
		count = 2;
		System.out.println("");
		System.out.println("");
		System.out.println("where did it happen?");
		answer.setWhereAnswer(in.nextLine());
		answer.setWhereAnswer(in.nextLine());
		while ((answer.getWhereAnswer().equals("1"))) {
			lastAnswer = answer.getWhereAnswer();
			System.out.println("");
			System.out.println("where " + count + ":");
			System.out.print("Q= ");
			answer.setWhereQuestion(in.nextLine());
			lastQuestion = answer.getWhereQuestion();
			System.out.print("R= ");
			answer.setWhereAnswer(in.nextLine());
			lastAnswer = answer.getWhereAnswer();
			count++;
			// to skip or keep the w
			answer.setWhereAnswer(in.nextLine());
			
		}
		if (!(answer.getWhereAnswer().equals("2"))) {
			if (answer.getWhereAnswer().equals("what")|| 
				answer.getWhereAnswer().equals("why")||
				answer.getWhereAnswer().equals("how")||
				answer.getWhereAnswer().equals("who")||
				answer.getWhereAnswer().equals("where")||
				answer.getWhereAnswer().equals("when")) {
				
				callingQuestion(answer.getWhereAnswer());
			}else {
				System.out.println("that is not a question");
			}
			
		}
	}

	public void when() {
		// when
		count = 2;
		System.out.println("");
		System.out.println("");
		System.out.println("when did it happen?");
		answer.setWhenAnswer(in.nextLine());
		answer.setWhenAnswer(in.nextLine());
		while ((answer.getWhenAnswer().equals("1"))) {
			lastAnswer = answer.getWhenAnswer();
			System.out.println("");
			System.out.println("when " + count + ":");
			System.out.print("Q= ");
			answer.setWhenQuestion(in.nextLine());
			lastQuestion = answer.getWhenQuestion();
			System.out.print("R= ");
			answer.setWhenAnswer(in.nextLine());
			lastAnswer = answer.getWhenAnswer();
			count++;
			// to skip or keep the w
			answer.setWhenAnswer(in.nextLine());
			
		}
		if (!(answer.getWhenAnswer().equals("2"))) {
			if (answer.getWhenAnswer().equals("what")|| 
				answer.getWhenAnswer().equals("why")||
				answer.getWhenAnswer().equals("how")||
				answer.getWhenAnswer().equals("who")||
				answer.getWhenAnswer().equals("where")||
				answer.getWhenAnswer().equals("when")) {
				
				callingQuestion(answer.getWhenAnswer());
			}else {
				System.out.println("that is not a question");
			}
			
		}

	}

	public void callingQuestion(String skipOrKeep) {
		if (skipOrKeep.equals("what")) {
			what();
		}
		if (skipOrKeep.equals("why")) {
			why();
		}
		if (skipOrKeep.equals("how") ) {
			how();
		}
		if (skipOrKeep.equals("who")) {
			who();
		}
		if (skipOrKeep.equals("where")) {
			where();
		}
		if (skipOrKeep.equals("when")) {
			when();
		}
	}

}
